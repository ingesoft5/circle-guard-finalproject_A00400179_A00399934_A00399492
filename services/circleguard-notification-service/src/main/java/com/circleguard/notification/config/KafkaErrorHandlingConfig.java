package com.circleguard.notification.config;

import com.fasterxml.jackson.core.JsonProcessingException;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.common.TopicPartition;
import org.apache.kafka.common.serialization.StringSerializer;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.core.DefaultKafkaProducerFactory;
import org.springframework.kafka.core.KafkaOperations;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.listener.CommonErrorHandler;
import org.springframework.kafka.listener.DeadLetterPublishingRecoverer;
import org.springframework.kafka.listener.DefaultErrorHandler;
import org.springframework.util.backoff.FixedBackOff;

import java.util.HashMap;
import java.util.Map;

/**
 * Dead Letter Topic (HU-12) for the Kafka consumers of notification-service. Same pattern as promotion-service
 * (each service is deployed on its own, so the class is not shared).
 *
 * <p><b>Problem it solves:</b> the three listeners caught every exception and only logged it, so an event that
 * could not be processed (a malformed payload, the auth-service being down while an alert is resolved) was
 * lost for good. Now it is retried a bounded number of times and then published to {@code <topic>.DLT}.
 *
 * <p><b>Which failures are retried:</b> transient ones (for example the auth-service not answering). A
 * malformed payload cannot be fixed by retrying: {@link JsonProcessingException}, {@link ClassCastException}
 * and {@link IllegalArgumentException} go straight to the DLT. The consumers read plain strings, so a record
 * can never fail to deserialize.
 *
 * <p><b>Delivery semantics:</b> at least once. Delivering to the channels (e-mail, SMS, push) is asynchronous
 * and its failures are handled by the retry of each channel, so they never reach this handler; what is retried
 * here is what runs before that. A record that fails halfway through a listener can be processed again.
 *
 * <p>Configuration (defaults are safe, no credentials):
 * {@code circleguard.kafka.consumer.retry.max-retries} (default 2) and
 * {@code circleguard.kafka.consumer.retry.backoff-ms} (default 1000).
 */
@Configuration
public class KafkaErrorHandlingConfig {

    public static final String DEAD_LETTER_SUFFIX = ".DLT";

    @Bean
    public CommonErrorHandler kafkaConsumerErrorHandler(
            KafkaTemplate<?, ?> kafkaTemplate,
            @Value("${circleguard.kafka.consumer.retry.max-retries:2}") long maxRetries,
            @Value("${circleguard.kafka.consumer.retry.backoff-ms:1000}") long backoffMs) {
        return build(stringTemplateLike(kafkaTemplate), maxRetries, backoffMs);
    }

    /** Builds the handler; also used by the tests to exercise the real thing. */
    public static DefaultErrorHandler build(KafkaOperations<?, ?> operations, long maxRetries, long backoffMs) {
        DeadLetterPublishingRecoverer recoverer = new DeadLetterPublishingRecoverer(operations,
                // Partition -1: let the producer pick it, so the DLT does not need to mirror the source partitions.
                KafkaErrorHandlingConfig::deadLetterPartition);
        DefaultErrorHandler handler = new DefaultErrorHandler(recoverer, new FixedBackOff(backoffMs, maxRetries));
        handler.addNotRetryableExceptions(JsonProcessingException.class, ClassCastException.class, IllegalArgumentException.class);
        return handler;
    }

    private static TopicPartition deadLetterPartition(ConsumerRecord<?, ?> record, Exception exception) {
        return new TopicPartition(record.topic() + DEAD_LETTER_SUFFIX, -1);
    }

    /**
     * A producer with the same connection settings as {@code template} but String values: the consumers read
     * plain strings, so the original payload must reach the DLT unchanged (the application template serializes
     * values as JSON, which would wrap it in quotes).
     */
    private static KafkaTemplate<String, String> stringTemplateLike(KafkaTemplate<?, ?> template) {
        Map<String, Object> properties = new HashMap<>();
        if (template.getProducerFactory() != null && template.getProducerFactory().getConfigurationProperties() != null) {
            properties.putAll(template.getProducerFactory().getConfigurationProperties());
        }
        properties.put("key.serializer", StringSerializer.class);
        properties.put("value.serializer", StringSerializer.class);
        return new KafkaTemplate<>(new DefaultKafkaProducerFactory<String, String>(properties));
    }
}
