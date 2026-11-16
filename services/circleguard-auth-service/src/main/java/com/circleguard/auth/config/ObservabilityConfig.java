package com.circleguard.auth.config;

import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import io.github.resilience4j.micrometer.tagged.TaggedCircuitBreakerMetrics;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * HU-13: publishes the same Circuit Breaker instance used by {@link com.circleguard.auth.client.IdentityClient}
 * as Micrometer metrics ({@code resilience4j_circuitbreaker_state} and friends).
 */
@Configuration
public class ObservabilityConfig {

    @Bean
    public CircuitBreakerRegistry circuitBreakerRegistry() {
        return CircuitBreakerRegistry.ofDefaults();
    }

    @Bean
    public TaggedCircuitBreakerMetrics identityCircuitBreakerMetrics(CircuitBreakerRegistry registry,
                                                                     MeterRegistry meterRegistry) {
        TaggedCircuitBreakerMetrics metrics = TaggedCircuitBreakerMetrics.ofCircuitBreakerRegistry(registry);
        metrics.bindTo(meterRegistry);
        return metrics;
    }
}
