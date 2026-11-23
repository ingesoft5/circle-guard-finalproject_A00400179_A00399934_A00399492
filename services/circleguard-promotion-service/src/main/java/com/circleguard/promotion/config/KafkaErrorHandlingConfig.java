package com.circleguard.promotion.config;

import com.circleguard.promotion.exception.FenceException;
import org.apache.kafka.common.TopicPartition;
import org.apache.kafka.common.serialization.ByteArraySerializer;
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
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Dead Letter Topic (HU-12) for the Kafka consumers of promotion-service.
 *
 * <p><b>Problem it solves:</b> the listeners used to catch every exception and only log it, so an event that
 * could not be processed was lost for good. Now a failing record is retried a bounded number of times and,
 * if it still fails, published to {@code <original topic>.DLT} where it can be inspected and replayed. The
 * consumer then moves on, so one bad record never blocks the partition.
 *
 * <p><b>Which failures are retried:</b> transient ones (for example Neo4j or Redis being briefly down).
 * Failures that retrying cannot fix go straight to the DLT: malformed payloads ({@link ClassCastException},
 * {@link IllegalArgumentException}), business rule rejections ({@link FenceException}) and records that cannot
 * even be deserialized. The last case relies on {@code ErrorHandlingDeserializer} (see application.yml): it
 * turns a deserialization failure into a record carrying the error, instead of an exception thrown from
 * {@code poll()} that would make the consumer read the same bytes forever. The raw bytes are published to the
 * DLT unchanged, through a second producer that uses {@link ByteArraySerializer}.
 *
 * <p>Spring Boot applies the {@link CommonErrorHandler} bean to every {@code @KafkaListener} container
 * factory, so no listener needs to change except to stop swallowing exceptions.
 *
 * <p>Configuration (defaults are safe, no credentials):
 * <ul>
 *   <li>{@code circleguard.kafka.consumer.retry.max-retries} (default 2): retries after the first delivery,
 *       so a failing record is delivered 3 times in total.</li>
 *   <li>{@code circleguard.kafka.consumer.retry.backoff-ms} (default 1000): pause between deliveries.</li>
 * </ul>
 * The {@code .DLT} topics must exist (or the broker must auto-create them) with at least as many partitions
 * as the source topic is read from; the destination partition is chosen by the producer.
 */
@Configuration
public class KafkaErrorHandlingConfig {

    public static final String DEAD_LETTER_SUFFIX = ".DLT";

    @Bean
    public CommonErrorHandler kafkaConsumerErrorHandler(
            KafkaTemplate<?, ?> kafkaTemplate,
            @Value("${circleguard.kafka.consumer.retry.max-retries:2}") long maxRetries,
            @Value("${circleguard.kafka.consumer.retry.backoff-ms:1000}") long backoffMs) {
        return build(kafkaTemplate, bytesTemplateLike(kafkaTemplate), maxRetries, backoffMs);
    }

    /** Builds the handler; also used by the integration tests to exercise the real thing against a real broker. */
    public static DefaultErrorHandler build(KafkaOperations<?, ?> operations, long maxRetries, long backoffMs) {
        return build(operations, null, maxRetries, backoffMs);
    }

    /**
     * @param bytesOperations producer for values that are raw bytes (records that failed to deserialize);
     *                        {@code null} when only one kind of value has to be published
     */
    public static DefaultErrorHandler build(KafkaOperations<?, ?> operations, KafkaOperations<?, ?> bytesOperations,
            long maxRetries, long backoffMs) {
        DeadLetterPublishingRecoverer recoverer;
        // Partition -1: let the producer pick it, so the DLT does not need to mirror the source partitions.
        if (bytesOperations == null) {
            recoverer = new DeadLetterPublishingRecoverer(operations, KafkaErrorHandlingConfig::deadLetterPartition);
        } else {
            // Ordered: the first template whose value type matches is used, so byte[] must come before Object.
            Map<Class<?>, KafkaOperations<?, ?>> templates = new LinkedHashMap<>();
            templates.put(byte[].class, bytesOperations);
            templates.put(Object.class, operations);
            recoverer = new DeadLetterPublishingRecoverer(templates, KafkaErrorHandlingConfig::deadLetterPartition);
        }
        DefaultErrorHandler handler = new DefaultErrorHandler(recoverer, new FixedBackOff(backoffMs, maxRetries));
        // DeserializationException is already not retryable by default in Spring Kafka.
        handler.addNotRetryableExceptions(ClassCastException.class, IllegalArgumentException.class, FenceException.class);
        return handler;
    }

    private static TopicPartition deadLetterPartition(org.apache.kafka.clients.consumer.ConsumerRecord<?, ?> record, Exception exception) {
        return new TopicPartition(record.topic() + DEAD_LETTER_SUFFIX, -1);
    }

    /** A producer with the same connection settings as {@code template} but raw byte values. */
    private static KafkaTemplate<String, byte[]> bytesTemplateLike(KafkaTemplate<?, ?> template) {
        Map<String, Object> properties = new HashMap<>();
        if (template.getProducerFactory() != null && template.getProducerFactory().getConfigurationProperties() != null) {
            properties.putAll(template.getProducerFactory().getConfigurationProperties());
        }
        properties.put("key.serializer", StringSerializer.class); // the consumers read String keys
        properties.put("value.serializer", ByteArraySerializer.class);
        return new KafkaTemplate<>(new DefaultKafkaProducerFactory<String, byte[]>(properties));
    }
}
