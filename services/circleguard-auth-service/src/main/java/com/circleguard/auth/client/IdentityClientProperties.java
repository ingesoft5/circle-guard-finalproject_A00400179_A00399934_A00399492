package com.circleguard.auth.client;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import java.time.Duration;

/**
 * External Configuration (HU-12): everything {@link IdentityClient} needs to reach identity-service
 * lives here and can be overridden without touching the code.
 *
 * <p>Property prefix {@code circleguard.identity-service}. With environment variables, Spring Boot's
 * relaxed binding maps {@code circleguard.identity-service.url} to {@code CIRCLEGUARD_IDENTITYSERVICE_URL},
 * {@code ...read-timeout} to {@code CIRCLEGUARD_IDENTITYSERVICE_READTIMEOUT} and
 * {@code ...circuit-breaker.minimum-number-of-calls} to
 * {@code CIRCLEGUARD_IDENTITYSERVICE_CIRCUITBREAKER_MINIMUMNUMBEROFCALLS}.
 *
 * <p>The defaults are safe for local development (the same address the client always used) and
 * contain no credentials. A deployment must set the URL (for example {@code http://identity:8083}).
 */
@Component
@ConfigurationProperties(prefix = "circleguard.identity-service")
@Getter
@Setter
public class IdentityClientProperties {

    /** Base URL of identity-service, without a trailing path. */
    private String url = "http://localhost:8083";

    /** Maximum time to open the connection. */
    private Duration connectTimeout = Duration.ofSeconds(2);

    /** Maximum time to wait for the answer. A slower answer counts as a failure of the circuit. */
    private Duration readTimeout = Duration.ofSeconds(3);

    private Breaker circuitBreaker = new Breaker();

    /** Circuit Breaker thresholds (see the Resilience4j documentation for each one). */
    @Getter
    @Setter
    public static class Breaker {
        /** Percentage of failed calls in the window that opens the circuit. */
        private float failureRateThreshold = 50;
        /** Number of calls the failure rate is computed over. */
        private int slidingWindowSize = 10;
        /** Calls needed before the failure rate is evaluated at all. */
        private int minimumNumberOfCalls = 5;
        /** Time the circuit stays open before it lets a few trial calls through. */
        private Duration waitDurationInOpenState = Duration.ofSeconds(10);
        /** Trial calls allowed while half-open; if they succeed the circuit closes. */
        private int permittedCallsInHalfOpenState = 3;
    }
}
