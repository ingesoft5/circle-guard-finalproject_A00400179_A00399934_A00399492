package com.circleguard.it;

import com.circleguard.promotion.config.KafkaErrorHandlingConfig;
import com.circleguard.promotion.exception.FenceException;
import com.circleguard.promotion.model.jpa.SystemSettings;
import com.circleguard.promotion.repository.jpa.SystemSettingsRepository;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.apache.kafka.common.serialization.StringSerializer;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.kafka.core.DefaultKafkaConsumerFactory;
import org.springframework.kafka.core.DefaultKafkaProducerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.listener.ContainerProperties;
import org.springframework.kafka.listener.KafkaMessageListenerContainer;
import org.springframework.kafka.listener.MessageListener;
import org.springframework.kafka.support.serializer.JsonSerializer;

import java.time.Duration;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;

/**
 * HU-12 · Dead Letter Topic, against a real Kafka broker.
 *
 * <p>The first test drives the real promotion-service consumer with a malformed event. The others run the
 * real {@link KafkaErrorHandlingConfig} error handler with a listener that fails on purpose (injected
 * faults), so the exact number of deliveries can be asserted.
 */
class DeadLetterTopicIntegrationTest {

    private static final long MAX_RETRIES = 2;
    private static final long BACKOFF_MS = 100;

    @BeforeAll
    static void environment() throws Exception {
        IntegrationEnvironment.start();
        // Seed the settings before any status update runs: promotion caches getSettings(), including an
        // empty result, for 5 minutes, and the other integration tests need the row to be there.
        SystemSettingsRepository settings = IntegrationEnvironment.promotion().getBean(SystemSettingsRepository.class);
        if (settings.count() == 0) {
            settings.save(SystemSettings.builder().unconfirmedFencingEnabled(true).autoThresholdSeconds(3600L)
                    .mandatoryFenceDays(14).encounterWindowDays(14).build());
        }
    }

    @Test
    @DisplayName("HU-12: a malformed survey event is dead-lettered by the real promotion consumer, which keeps working")
    void malformedSurveyEvent_IsDeadLettered_AndConsumptionContinues() {
        String poisonId = "poison-" + UUID.randomUUID();
        Map<String, Object> malformed = new HashMap<>();
        malformed.put("anonymousId", poisonId);
        malformed.put("hasSymptoms", "yes"); // a String where the listener expects a Boolean
        publishJson("survey.submitted", poisonId, malformed);

        assertDeadLettered("survey.submitted" + KafkaErrorHandlingConfig.DEAD_LETTER_SUFFIX, poisonId);

        // The consumer was not blocked by the bad record: a valid survey sent afterwards is processed.
        UUID healthy = UUID.randomUUID();
        IntegrationEnvironment.createUser(healthy.toString(), "ACTIVE", null);
        IntegrationEnvironment.submitSurvey(healthy, true);
        await().atMost(Duration.ofSeconds(60))
                .untilAsserted(() -> assertThat(IntegrationEnvironment.graphStatus(healthy.toString())).isEqualTo("SUSPECT"));
    }

    @Test
    @DisplayName("HU-12: a transient failure is retried and, once it clears, nothing reaches the dead letter topic")
    void transientFailure_IsRetriedAndRecovers() {
        String topic = "hu12.transient." + UUID.randomUUID();
        String payload = "payload-" + UUID.randomUUID();
        AtomicInteger deliveries = new AtomicInteger();

        KafkaMessageListenerContainer<String, String> container =
                runConsumer(topic, payload, deliveries, 2, new IllegalStateException("neo4j briefly down"));
        try {
            await().atMost(Duration.ofSeconds(30)).untilAsserted(() -> assertThat(deliveries.get()).isEqualTo(3));
            assertThat(KafkaProbe.read(topic + ".DLT", payload::equals, Duration.ofSeconds(4))).isEmpty();
            assertThat(deliveries.get()).isEqualTo(3);
        } finally {
            container.stop();
        }
    }

    @Test
    @DisplayName("HU-12: a failure that never clears is delivered 1 + retries times and then dead-lettered")
    void persistentFailure_IsRetriedThenDeadLettered() {
        String topic = "hu12.persistent." + UUID.randomUUID();
        String payload = "payload-" + UUID.randomUUID();
        AtomicInteger deliveries = new AtomicInteger();

        KafkaMessageListenerContainer<String, String> container =
                runConsumer(topic, payload, deliveries, -1, new IllegalStateException("neo4j down"));
        try {
            assertDeadLettered(topic + ".DLT", payload);
            assertThat(deliveries.get()).isEqualTo(1 + MAX_RETRIES);
        } finally {
            container.stop();
        }
    }

    @Test
    @DisplayName("HU-12: malformed data and business rule rejections are not retried: straight to the dead letter topic")
    void nonRetryableFailures_GoStraightToTheDeadLetterTopic() {
        for (RuntimeException failure : new RuntimeException[]{
                new IllegalArgumentException("bad payload"),
                new ClassCastException("wrong type"),
                new FenceException("user is still inside the mandatory fence window")}) {
            String topic = "hu12.nonretryable." + UUID.randomUUID();
            String payload = "payload-" + UUID.randomUUID();
            AtomicInteger deliveries = new AtomicInteger();

            KafkaMessageListenerContainer<String, String> container =
                    runConsumer(topic, payload, deliveries, -1, failure);
            try {
                assertDeadLettered(topic + ".DLT", payload);
                assertThat(deliveries.get()).as(failure.getClass().getSimpleName() + " must not be retried").isEqualTo(1);
            } finally {
                container.stop();
            }
        }
    }

    /**
     * Publishes {@code payload} to {@code topic} and consumes it with the real error handler. The listener
     * fails the first {@code failuresBeforeSuccess} deliveries (always when negative) with {@code failure}.
     */
    private static KafkaMessageListenerContainer<String, String> runConsumer(String topic, String payload,
            AtomicInteger deliveries, int failuresBeforeSuccess, RuntimeException failure) {
        publishString(topic, payload);

        ContainerProperties properties = new ContainerProperties(topic);
        properties.setMessageListener((MessageListener<String, String>) record -> {
            int delivery = deliveries.incrementAndGet();
            if (failuresBeforeSuccess < 0 || delivery <= failuresBeforeSuccess) {
                throw failure;
            }
        });
        KafkaMessageListenerContainer<String, String> container = new KafkaMessageListenerContainer<>(
                new DefaultKafkaConsumerFactory<String, String>(Map.of(
                        ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, IntegrationEnvironment.bootstrapServers(),
                        ConsumerConfig.GROUP_ID_CONFIG, "hu12-" + UUID.randomUUID(),
                        ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest",
                        ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class,
                        ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class)),
                properties);
        container.setCommonErrorHandler(KafkaErrorHandlingConfig.build(stringTemplate(), MAX_RETRIES, BACKOFF_MS));
        container.start();
        return container;
    }

    /** The topic may not exist yet when the probe subscribes, so ask again until the record shows up. */
    private static void assertDeadLettered(String deadLetterTopic, String payloadFragment) {
        await().atMost(Duration.ofSeconds(60)).untilAsserted(() ->
                assertThat(KafkaProbe.read(deadLetterTopic, value -> value.contains(payloadFragment), Duration.ofSeconds(3)))
                        .isNotEmpty());
    }

    private static void publishString(String topic, String value) {
        try (KafkaProducer<String, String> producer = new KafkaProducer<>(Map.<String, Object>of(
                ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, IntegrationEnvironment.bootstrapServers(),
                ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class,
                ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class))) {
            producer.send(new ProducerRecord<>(topic, "key", value));
            producer.flush();
        }
    }

    /** Like form-service does: JSON with type headers, so the promotion consumer can deserialize it. */
    private static void publishJson(String topic, String key, Map<String, Object> value) {
        try (KafkaProducer<String, Object> producer = new KafkaProducer<>(Map.<String, Object>of(
                ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, IntegrationEnvironment.bootstrapServers(),
                ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class,
                ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, JsonSerializer.class))) {
            producer.send(new ProducerRecord<>(topic, key, value));
            producer.flush();
        }
    }

    private static KafkaTemplate<String, String> stringTemplate() {
        return new KafkaTemplate<>(new DefaultKafkaProducerFactory<String, String>(Map.<String, Object>of(
                ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, IntegrationEnvironment.bootstrapServers(),
                ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class,
                ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class)));
    }
}
