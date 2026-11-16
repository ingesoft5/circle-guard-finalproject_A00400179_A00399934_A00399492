package com.circleguard.promotion.config;

import com.circleguard.promotion.exception.FenceException;
import org.apache.kafka.common.TopicPartition;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.core.KafkaOperations;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.listener.CommonErrorHandler;
import org.springframework.kafka.listener.DeadLetterPublishingRecoverer;
import org.springframework.kafka.listener.DefaultErrorHandler;
import org.springframework.util.backoff.FixedBackOff;

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
 * {@link IllegalArgumentException}) and business rule rejections ({@link FenceException}).
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
            KafkaTemplate<String, Object> kafkaTemplate,
            @Value("${circleguard.kafka.consumer.retry.max-retries:2}") long maxRetries,
            @Value("${circleguard.kafka.consumer.retry.backoff-ms:1000}") long backoffMs) {
        return build(kafkaTemplate, maxRetries, backoffMs);
    }

    /** Builds the handler; also used by the integration tests to exercise the real thing against a real broker. */
    public static DefaultErrorHandler build(KafkaOperations<?, ?> operations, long maxRetries, long backoffMs) {
        DeadLetterPublishingRecoverer recoverer = new DeadLetterPublishingRecoverer(operations,
                // Partition -1: let the producer pick it, so the DLT does not need to mirror the source partitions.
                (record, exception) -> new TopicPartition(record.topic() + DEAD_LETTER_SUFFIX, -1));
        DefaultErrorHandler handler = new DefaultErrorHandler(recoverer, new FixedBackOff(backoffMs, maxRetries));
        handler.addNotRetryableExceptions(ClassCastException.class, IllegalArgumentException.class, FenceException.class);
        return handler;
    }
}
