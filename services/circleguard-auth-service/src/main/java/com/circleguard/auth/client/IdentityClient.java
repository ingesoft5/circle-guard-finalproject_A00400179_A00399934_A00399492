package com.circleguard.auth.client;

import io.github.resilience4j.circuitbreaker.CallNotPermittedException;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerConfig;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.stereotype.Component;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.HttpServerErrorException;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestTemplate;

import java.util.Map;
import java.util.UUID;

/**
 * Client of identity-service, protected with a Circuit Breaker (HU-12, Resilience4j).
 *
 * <p><b>What counts as a failure:</b> I/O errors and timeouts ({@link ResourceAccessException}) and
 * 5xx answers ({@link HttpServerErrorException}). 4xx answers are business errors, not a sick
 * dependency, so they neither open the circuit nor count as failures.
 *
 * <p><b>What happens when it fails:</b> the caller gets an {@link IdentityServiceUnavailableException}
 * quickly. There is deliberately no degraded fallback: without identity-service no anonymous id exists,
 * and inventing one would break the anonymization guarantee.
 *
 * <p>Everything configurable (URL, timeouts, thresholds) comes from {@link IdentityClientProperties}.
 * Metrics integration (HU-13): {@link #getCircuitBreaker()} exposes the instance so Micrometer can bind it
 * without changing this class.
 */
@Component
@Slf4j
public class IdentityClient {

    private static final String MAP_PATH = "/api/v1/identities/map";

    private final RestTemplate restTemplate;
    private final String mapUrl;
    private final CircuitBreaker circuitBreaker;

    /** Defaults only (same address the client always used). Kept for tests and local use. */
    public IdentityClient() {
        this(new IdentityClientProperties());
    }

    @Autowired
    public IdentityClient(IdentityClientProperties properties) {
        this.mapUrl = properties.getUrl().replaceAll("/+$", "") + MAP_PATH;
        this.restTemplate = new RestTemplateBuilder()
                .setConnectTimeout(properties.getConnectTimeout())
                .setReadTimeout(properties.getReadTimeout())
                .build();

        IdentityClientProperties.Breaker breaker = properties.getCircuitBreaker();
        CircuitBreakerConfig config = CircuitBreakerConfig.custom()
                .failureRateThreshold(breaker.getFailureRateThreshold())
                .slidingWindowSize(breaker.getSlidingWindowSize())
                .minimumNumberOfCalls(breaker.getMinimumNumberOfCalls())
                .waitDurationInOpenState(breaker.getWaitDurationInOpenState())
                .permittedNumberOfCallsInHalfOpenState(breaker.getPermittedCallsInHalfOpenState())
                .recordException(IdentityClient::isDependencyFailure)
                .ignoreExceptions(HttpClientErrorException.class)
                .build();
        this.circuitBreaker = CircuitBreaker.of("identity-service", config);
        this.circuitBreaker.getEventPublisher().onStateTransition(event ->
                log.warn("Circuit breaker '{}' changed state: {}", event.getCircuitBreakerName(), event.getStateTransition()));
    }

    public UUID getAnonymousId(String realIdentity) {
        Map<String, String> request = Map.of("realIdentity", realIdentity);
        Map<?, ?> response;
        try {
            response = circuitBreaker.executeSupplier(() -> restTemplate.postForObject(mapUrl, request, Map.class));
        } catch (CallNotPermittedException e) {
            throw new IdentityServiceUnavailableException("identity-service circuit is open", e);
        } catch (ResourceAccessException | HttpServerErrorException e) {
            throw new IdentityServiceUnavailableException("identity-service call failed: " + e.getMessage(), e);
        }
        return UUID.fromString(response.get("anonymousId").toString());
    }

    /** The circuit of this client, for metrics (HU-13) and tests. */
    public CircuitBreaker getCircuitBreaker() {
        return circuitBreaker;
    }

    private static boolean isDependencyFailure(Throwable t) {
        return t instanceof ResourceAccessException || t instanceof HttpServerErrorException;
    }

    /**
     * identity-service cannot be reached right now (error, timeout or open circuit). It is a
     * {@link RestClientException} so existing callers that handle that type keep working.
     */
    public static class IdentityServiceUnavailableException extends RestClientException {
        public IdentityServiceUnavailableException(String message, Throwable cause) {
            super(message, cause);
        }
    }
}
