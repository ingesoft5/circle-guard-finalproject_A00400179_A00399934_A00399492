package com.circleguard.notification.service;

import com.circleguard.notification.config.KafkaErrorHandlingConfig;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.kafka.clients.consumer.Consumer;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.kafka.core.KafkaOperations;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.listener.DefaultErrorHandler;
import org.springframework.kafka.listener.MessageListenerContainer;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestTemplate;

import java.util.concurrent.CompletableFuture;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * HU-12 · Dead Letter Topic in notification-service. The listeners used to swallow every exception; these
 * tests inject faults (malformed payloads, an auth-service that does not answer) and check that the failure
 * now reaches the error handler, and that the handler retries or dead-letters as designed. The end-to-end
 * behaviour against a real broker is in tests/integration (DeadLetterTopicIntegrationTest).
 */
class DeadLetterHandlingTest {

    private final ObjectMapper objectMapper = new ObjectMapper();

    // ------------------------------------------------------------------ the listeners no longer swallow errors

    @Test
    void statusChangeListener_WithAMalformedEvent_PropagatesInsteadOfDroppingIt() {
        NotificationDispatcher dispatcher = mock(NotificationDispatcher.class);
        ExposureNotificationListener listener = new ExposureNotificationListener(dispatcher, objectMapper, mock(LmsService.class));

        assertThatThrownBy(() -> listener.handleStatusChange("{not json")).isInstanceOf(JsonProcessingException.class);
        verifyNoInteractions(dispatcher);
    }

    @Test
    void statusChangeListener_WithAValidEvent_StillDispatches() throws Exception {
        NotificationDispatcher dispatcher = mock(NotificationDispatcher.class);
        LmsService lms = mock(LmsService.class);
        new ExposureNotificationListener(dispatcher, objectMapper, lms)
                .handleStatusChange("{\"anonymousId\":\"user-1\",\"status\":\"CONFIRMED\"}");

        verify(dispatcher).dispatch("user-1", "CONFIRMED");
        verify(lms).syncRemoteAttendance("user-1", "CONFIRMED");
    }

    @Test
    void circleFencedListener_WithAMalformedEvent_Propagates() {
        RoomReservationService rooms = mock(RoomReservationService.class);
        CircleFencedListener listener = new CircleFencedListener(objectMapper, rooms);

        assertThatThrownBy(() -> listener.handleCircleFenced("not json at all")).isInstanceOf(JsonProcessingException.class);
        verifyNoInteractions(rooms);
    }

    @Test
    void circleFencedListener_CancelsTheReservationOnlyWhenThereIsALocation() throws Exception {
        RoomReservationService rooms = mock(RoomReservationService.class);
        CircleFencedListener listener = new CircleFencedListener(objectMapper, rooms);

        listener.handleCircleFenced("{\"circleId\":\"c1\",\"locationId\":\"room-9\"}");
        verify(rooms).cancelReservation("c1", "room-9");

        listener.handleCircleFenced("{\"circleId\":\"c2\"}");
        verify(rooms, never()).cancelReservation(anyString(), org.mockito.ArgumentMatchers.eq(null));
    }

    @Test
    void priorityAlertListener_WithAMalformedEvent_Propagates() {
        PriorityAlertListener listener = new PriorityAlertListener(objectMapper, mock(TemplateService.class));

        assertThatThrownBy(() -> listener.handlePriorityAlert("{broken")).isInstanceOf(JsonProcessingException.class);
    }

    @Test
    void priorityAlertListener_WhenTheAuthServiceDoesNotAnswer_PropagatesSoItCanBeRetried() {
        PriorityAlertListener listener = new PriorityAlertListener(objectMapper, mock(TemplateService.class));
        RestTemplate restTemplate = mock(RestTemplate.class);
        when(restTemplate.getForObject(anyString(), any(Class.class))).thenThrow(new ResourceAccessException("auth-service down"));
        ReflectionTestUtils.setField(listener, "restTemplate", restTemplate);
        ReflectionTestUtils.setField(listener, "authApiUrl", "http://auth");

        assertThatThrownBy(() -> listener.handlePriorityAlert("{\"eventType\":\"CONFIRMED_CASE\",\"affectedCount\":1}"))
                .isInstanceOf(ResourceAccessException.class);
    }

    // ------------------------------------------------------------------ the error handler

    @Test
    @SuppressWarnings("unchecked")
    void aMalformedPayloadIsDeadLetteredAtOnceWithoutRetries() {
        KafkaOperations<String, String> operations = operationsThatAcceptEverything();
        DefaultErrorHandler handler = KafkaErrorHandlingConfig.build(operations, 2, 1);
        ConsumerRecord<String, String> record = new ConsumerRecord<>("alert.priority", 0, 7L, "k", "{broken");

        boolean recovered = handler.handleOne(new JsonProcessingException("malformed") { }, record,
                mock(Consumer.class), mock(MessageListenerContainer.class));

        assertThat(recovered).as("not retryable: recovered (dead-lettered) on the first failure").isTrue();
        ArgumentCaptor<ProducerRecord<String, String>> sent = ArgumentCaptor.forClass(ProducerRecord.class);
        verify(operations).send(sent.capture());
        assertThat(sent.getValue().topic()).isEqualTo("alert.priority.DLT");
        assertThat(sent.getValue().value()).isEqualTo("{broken");
    }

    @Test
    @SuppressWarnings("unchecked")
    void aTransientFailureIsRetriedAndNotDeadLetteredYet() {
        KafkaOperations<String, String> operations = operationsThatAcceptEverything();
        DefaultErrorHandler handler = KafkaErrorHandlingConfig.build(operations, 2, 1);
        ConsumerRecord<String, String> record = new ConsumerRecord<>("alert.priority", 0, 7L, "k", "{}");

        boolean recovered = handler.handleOne(new ResourceAccessException("auth-service down"), record,
                mock(Consumer.class), mock(MessageListenerContainer.class));

        assertThat(recovered).as("retryable: the record must be delivered again").isFalse();
        verify(operations, never()).send(any(ProducerRecord.class));
    }

    @Test
    void theBeanUsesTheConfiguredRetries() {
        var handler = new KafkaErrorHandlingConfig().kafkaConsumerErrorHandler(mock(KafkaTemplate.class), 3, 500);

        assertThat(handler).isInstanceOf(DefaultErrorHandler.class);
    }

    @SuppressWarnings("unchecked")
    private static KafkaOperations<String, String> operationsThatAcceptEverything() {
        KafkaOperations<String, String> operations = mock(KafkaOperations.class);
        when(operations.send(any(ProducerRecord.class))).thenReturn(CompletableFuture.completedFuture(null));
        return operations;
    }
}
