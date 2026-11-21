package com.circleguard.auth.config;

import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertNotNull;

/** HU-13: the shared registry must publish the circuit breaker state as a Micrometer gauge. */
class ObservabilityConfigTest {

    @Test
    void publishesCircuitBreakerStateForTheSharedRegistry() {
        ObservabilityConfig config = new ObservabilityConfig();
        CircuitBreakerRegistry registry = config.circuitBreakerRegistry();
        SimpleMeterRegistry meterRegistry = new SimpleMeterRegistry();

        config.identityCircuitBreakerMetrics(registry, meterRegistry);
        registry.circuitBreaker("identity-service");

        assertNotNull(meterRegistry.find("resilience4j.circuitbreaker.state")
                .tag("name", "identity-service")
                .gauge());
    }
}
