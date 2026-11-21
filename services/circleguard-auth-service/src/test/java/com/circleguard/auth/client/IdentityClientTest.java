package com.circleguard.auth.client;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import io.github.resilience4j.circuitbreaker.CallNotPermittedException;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.SystemEnvironmentPropertySource;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.client.ExpectedCount;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestTemplate;

import java.io.IOException;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.content;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

class IdentityClientTest {

    private static final String URL = "http://localhost:8083/api/v1/identities/map";

    private IdentityClient client;
    private MockRestServiceServer server;

    @BeforeEach
    void setUp() {
        client = new IdentityClient();
        RestTemplate restTemplate = (RestTemplate) ReflectionTestUtils.getField(client, "restTemplate");
        server = MockRestServiceServer.bindTo(restTemplate).build();
    }

    @Test
    void getAnonymousId_PostsTheRealIdentityAndParsesTheAnswer() {
        UUID expected = UUID.randomUUID();
        server.expect(requestTo(URL))
                .andExpect(method(HttpMethod.POST))
                .andExpect(content().json("{\"realIdentity\":\"alice@example.com\"}"))
                .andRespond(withSuccess("{\"anonymousId\":\"" + expected + "\"}", MediaType.APPLICATION_JSON));

        assertThat(client.getAnonymousId("alice@example.com")).isEqualTo(expected);
        server.verify();
    }

    @Test
    void getAnonymousId_WhenTheIdentityServiceFails_Propagates() {
        server.expect(requestTo(URL)).andRespond(withServerError());

        assertThatThrownBy(() -> client.getAnonymousId("alice@example.com")).isInstanceOf(RestClientException.class);
    }

    @Test
    void getAnonymousId_WithAnEmptyBody_ReportsTheIdentityServiceAsUnavailable() {
        server.expect(requestTo(URL)).andRespond(withSuccess());

        assertThatThrownBy(() -> client.getAnonymousId("alice@example.com"))
                .isInstanceOf(IdentityClient.IdentityServiceUnavailableException.class)
                .hasMessageContaining("without an anonymousId");
    }

    @Test
    void getAnonymousId_WithoutTheAnonymousIdField_ReportsTheIdentityServiceAsUnavailable() {
        server.expect(requestTo(URL)).andRespond(withSuccess("{\"other\":\"x\"}", MediaType.APPLICATION_JSON));

        assertThatThrownBy(() -> client.getAnonymousId("alice@example.com"))
                .isInstanceOf(IdentityClient.IdentityServiceUnavailableException.class)
                .hasMessageContaining("without an anonymousId");
    }

    @Test
    void getAnonymousId_WithAMalformedAnonymousId_ReportsTheIdentityServiceAsUnavailable() {
        server.expect(requestTo(URL)).andRespond(withSuccess("{\"anonymousId\":\"not-a-uuid\"}", MediaType.APPLICATION_JSON));

        assertThatThrownBy(() -> client.getAnonymousId("alice@example.com"))
                .isInstanceOf(IdentityClient.IdentityServiceUnavailableException.class)
                .hasMessageContaining("invalid anonymousId");
    }

    // ------------------------------------------------------------------------------------------------
    // HU-12 · Circuit Breaker. A real HTTP server (JDK) plays identity-service and its faults are injected:
    // 500 answers, answers slower than the read timeout and 400 answers. No mocks of the breaker: the real
    // Resilience4j instance of the client is exercised and inspected.
    // ------------------------------------------------------------------------------------------------
    @Nested
    class CircuitBreakerWithInjectedFaults {

        private final AtomicReference<Mode> mode = new AtomicReference<>(Mode.OK);
        private final AtomicInteger hits = new AtomicInteger();
        private final UUID anonymousId = UUID.randomUUID();
        private HttpServer identity;
        private IdentityClient breakerClient;

        @BeforeEach
        void startIdentityService() throws IOException {
            identity = HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(), 0), 0);
            identity.setExecutor(Executors.newCachedThreadPool());
            identity.createContext("/api/v1/identities/map", this::handle);
            identity.start();

            IdentityClientProperties properties = new IdentityClientProperties();
            properties.setUrl("http://127.0.0.1:" + identity.getAddress().getPort());
            properties.setConnectTimeout(Duration.ofMillis(500));
            properties.setReadTimeout(Duration.ofMillis(300));
            properties.getCircuitBreaker().setSlidingWindowSize(4);
            properties.getCircuitBreaker().setMinimumNumberOfCalls(4);
            properties.getCircuitBreaker().setFailureRateThreshold(50);
            properties.getCircuitBreaker().setWaitDurationInOpenState(Duration.ofMillis(300));
            properties.getCircuitBreaker().setPermittedCallsInHalfOpenState(2);
            breakerClient = new IdentityClient(properties);
        }

        @AfterEach
        void stopIdentityService() {
            identity.stop(0);
            ((ExecutorService) identity.getExecutor()).shutdownNow();
        }

        @Test
        void staysClosedWhileIdentityServiceIsHealthy() {
            for (int i = 0; i < 6; i++) {
                assertThat(breakerClient.getAnonymousId("alice@example.com")).isEqualTo(anonymousId);
            }

            assertThat(breakerClient.getCircuitBreaker().getState()).isEqualTo(CircuitBreaker.State.CLOSED);
            assertThat(hits.get()).isEqualTo(6);
        }

        @Test
        void opensAtTheFailureThresholdAndThenRejectsWithoutCallingIdentityService() {
            mode.set(Mode.ERROR_500);
            failTimes(4);

            assertThat(breakerClient.getCircuitBreaker().getState()).isEqualTo(CircuitBreaker.State.OPEN);
            assertThat(hits.get()).isEqualTo(4);

            // OPEN: the call is rejected immediately and never reaches identity-service.
            assertThatThrownBy(() -> breakerClient.getAnonymousId("alice@example.com"))
                    .isInstanceOf(IdentityClient.IdentityServiceUnavailableException.class)
                    .hasCauseInstanceOf(CallNotPermittedException.class);
            assertThat(hits.get()).isEqualTo(4);
        }

        @Test
        void recoversThroughHalfOpenAndClosesAgainWhenIdentityServiceIsBack() throws InterruptedException {
            mode.set(Mode.ERROR_500);
            failTimes(4);
            assertThat(breakerClient.getCircuitBreaker().getState()).isEqualTo(CircuitBreaker.State.OPEN);

            mode.set(Mode.OK);
            Thread.sleep(450); // longer than waitDurationInOpenState (300 ms)

            // First trial call goes through: HALF_OPEN while the trial quota is not used up.
            assertThat(breakerClient.getAnonymousId("alice@example.com")).isEqualTo(anonymousId);
            assertThat(breakerClient.getCircuitBreaker().getState()).isEqualTo(CircuitBreaker.State.HALF_OPEN);

            // Second trial call succeeds: the circuit closes.
            assertThat(breakerClient.getAnonymousId("alice@example.com")).isEqualTo(anonymousId);
            assertThat(breakerClient.getCircuitBreaker().getState()).isEqualTo(CircuitBreaker.State.CLOSED);
        }

        @Test
        void reopensIfTheTrialCallsFail() throws InterruptedException {
            mode.set(Mode.ERROR_500);
            failTimes(4);
            Thread.sleep(450);

            failTimes(2); // both trial calls fail while still HALF_OPEN

            assertThat(breakerClient.getCircuitBreaker().getState()).isEqualTo(CircuitBreaker.State.OPEN);
        }

        @Test
        void aResponseSlowerThanTheReadTimeoutCountsAsAFailure() {
            mode.set(Mode.SLOW);
            long start = System.nanoTime();
            failTimes(4);
            long elapsedMs = Duration.ofNanos(System.nanoTime() - start).toMillis();

            assertThat(breakerClient.getCircuitBreaker().getState()).isEqualTo(CircuitBreaker.State.OPEN);
            // Without timeouts these calls would hang for the whole 1.5 s handler delay each.
            assertThat(elapsedMs).isLessThan(4 * 1500L);
        }

        @Test
        void clientErrorsAreBusinessErrorsAndDoNotOpenTheCircuit() {
            mode.set(Mode.BAD_REQUEST_400);

            for (int i = 0; i < 6; i++) {
                assertThatThrownBy(() -> breakerClient.getAnonymousId("alice@example.com"))
                        .isInstanceOf(HttpClientErrorException.class);
            }

            assertThat(breakerClient.getCircuitBreaker().getState()).isEqualTo(CircuitBreaker.State.CLOSED);
        }

        private void failTimes(int times) {
            for (int i = 0; i < times; i++) {
                assertThatThrownBy(() -> breakerClient.getAnonymousId("alice@example.com"))
                        .isInstanceOf(IdentityClient.IdentityServiceUnavailableException.class);
            }
        }

        private void handle(HttpExchange exchange) throws IOException {
            hits.incrementAndGet();
            exchange.getRequestBody().readAllBytes();
            try {
                switch (mode.get()) {
                    case OK -> reply(exchange, 200, "{\"anonymousId\":\"" + anonymousId + "\"}");
                    case ERROR_500 -> reply(exchange, 500, "{}");
                    case BAD_REQUEST_400 -> reply(exchange, 400, "{}");
                    case SLOW -> {
                        sleepQuietly(1500);
                        reply(exchange, 200, "{\"anonymousId\":\"" + anonymousId + "\"}");
                    }
                }
            } catch (IOException clientAlreadyGone) {
                // The client timed out and closed the connection: expected for SLOW.
            } finally {
                exchange.close();
            }
        }

        private void reply(HttpExchange exchange, int status, String body) throws IOException {
            byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().add("Content-Type", "application/json");
            exchange.sendResponseHeaders(status, bytes.length);
            exchange.getResponseBody().write(bytes);
        }

        private void sleepQuietly(long millis) {
            try {
                Thread.sleep(millis);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
    }

    // ------------------------------------------------------------------------------------------------
    // HU-12 · External Configuration. The client is configured from properties and environment variables,
    // not from constants, and changing them changes the behaviour without touching the logic.
    // ------------------------------------------------------------------------------------------------
    @Configuration
    @EnableConfigurationProperties
    static class BindingConfig {
    }

    @Nested
    class ExternalConfiguration {

        private final ApplicationContextRunner runner = new ApplicationContextRunner()
                .withUserConfiguration(BindingConfig.class, IdentityClientProperties.class, IdentityClient.class);

        @Test
        void defaultsAreSafeAndKeepTheAddressTheClientAlwaysUsed() {
            IdentityClientProperties defaults = new IdentityClientProperties();

            assertThat(defaults.getUrl()).isEqualTo("http://localhost:8083");
            assertThat(defaults.getConnectTimeout()).isEqualTo(Duration.ofSeconds(2));
            assertThat(defaults.getReadTimeout()).isEqualTo(Duration.ofSeconds(3));
            assertThat(defaults.getCircuitBreaker().getFailureRateThreshold()).isEqualTo(50f);
            assertThat(defaults.getCircuitBreaker().getMinimumNumberOfCalls()).isEqualTo(5);
            assertThat(ReflectionTestUtils.getField(new IdentityClient(), "mapUrl")).isEqualTo(URL);
        }

        @Test
        void bindsTheTypedPropertiesFromTheEnvironment() {
            runner.withPropertyValues(
                            "circleguard.identity-service.url=http://identity.internal:8083/",
                            "circleguard.identity-service.read-timeout=1s",
                            "circleguard.identity-service.circuit-breaker.failure-rate-threshold=25",
                            "circleguard.identity-service.circuit-breaker.sliding-window-size=2",
                            "circleguard.identity-service.circuit-breaker.minimum-number-of-calls=2")
                    .run(context -> {
                        IdentityClientProperties properties = context.getBean(IdentityClientProperties.class);
                        assertThat(properties.getUrl()).isEqualTo("http://identity.internal:8083/");
                        assertThat(properties.getReadTimeout()).isEqualTo(Duration.ofSeconds(1));

                        IdentityClient bound = context.getBean(IdentityClient.class);
                        // The trailing slash is normalised and the breaker was built from the properties.
                        assertThat(ReflectionTestUtils.getField(bound, "mapUrl"))
                                .isEqualTo("http://identity.internal:8083/api/v1/identities/map");
                        var breakerConfig = bound.getCircuitBreaker().getCircuitBreakerConfig();
                        assertThat(breakerConfig.getFailureRateThreshold()).isEqualTo(25f);
                        assertThat(breakerConfig.getSlidingWindowSize()).isEqualTo(2);
                        assertThat(breakerConfig.getMinimumNumberOfCalls()).isEqualTo(2);
                    });
        }

        @Test
        void environmentVariablesOverrideTheDefaultsThroughRelaxedBinding() {
            runner.withInitializer(context -> context.getEnvironment().getPropertySources().addFirst(
                            new SystemEnvironmentPropertySource("systemEnvironment", Map.<String, Object>of(
                                    "CIRCLEGUARD_IDENTITYSERVICE_URL", "http://identity:8083",
                                    "CIRCLEGUARD_IDENTITYSERVICE_CIRCUITBREAKER_MINIMUMNUMBEROFCALLS", "3"))))
                    .run(context -> {
                        IdentityClient bound = context.getBean(IdentityClient.class);
                        assertThat(ReflectionTestUtils.getField(bound, "mapUrl"))
                                .isEqualTo("http://identity:8083/api/v1/identities/map");
                        assertThat(bound.getCircuitBreaker().getCircuitBreakerConfig().getMinimumNumberOfCalls())
                                .isEqualTo(3);
                    });
        }

        @Test
        void changingOnlyTheConfigurationChangesWhenTheCircuitOpens() {
            String configuredUrl = "http://identity.internal:8083/api/v1/identities/map";

            // Same code, same two failures: only the configuration differs.
            IdentityClientProperties sensitive = new IdentityClientProperties();
            sensitive.setUrl("http://identity.internal:8083");
            sensitive.getCircuitBreaker().setSlidingWindowSize(2);
            sensitive.getCircuitBreaker().setMinimumNumberOfCalls(2);
            IdentityClientProperties patient = new IdentityClientProperties();
            patient.setUrl("http://identity.internal:8083");

            IdentityClient sensitiveClient = new IdentityClient(sensitive);
            IdentityClient patientClient = new IdentityClient(patient);
            for (IdentityClient configured : new IdentityClient[]{sensitiveClient, patientClient}) {
                RestTemplate template = (RestTemplate) ReflectionTestUtils.getField(configured, "restTemplate");
                MockRestServiceServer.bindTo(template).build()
                        .expect(ExpectedCount.manyTimes(), requestTo(configuredUrl)) // the configured URL is the one called
                        .andRespond(withServerError());
                for (int i = 0; i < 2; i++) {
                    assertThatThrownBy(() -> configured.getAnonymousId("alice@example.com"))
                            .isInstanceOf(IdentityClient.IdentityServiceUnavailableException.class);
                }
            }

            assertThat(sensitiveClient.getCircuitBreaker().getState()).isEqualTo(CircuitBreaker.State.OPEN);
            assertThat(patientClient.getCircuitBreaker().getState()).isEqualTo(CircuitBreaker.State.CLOSED);
        }
    }

    private enum Mode { OK, ERROR_500, BAD_REQUEST_400, SLOW }
}
