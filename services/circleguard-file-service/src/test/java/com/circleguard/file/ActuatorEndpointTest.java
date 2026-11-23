package com.circleguard.file;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.actuate.observability.AutoConfigureObservability;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.http.ResponseEntity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * HU-13: verifies that the service exposes the Prometheus endpoint and the Kubernetes probes.
 * The file service has no database, so the context starts without external middleware.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureObservability
class ActuatorEndpointTest {

    @Autowired
    private TestRestTemplate restTemplate;

    @Test
    void prometheusEndpointExposesJvmMetrics() {
        ResponseEntity<String> response = restTemplate.getForEntity("/actuator/prometheus", String.class);
        assertEquals(200, response.getStatusCode().value());
        assertTrue(response.getBody() != null && response.getBody().contains("jvm_"));
    }

    @Test
    void livenessAndReadinessProbesAreAvailable() {
        assertEquals(200, restTemplate.getForEntity("/actuator/health/liveness", String.class)
                .getStatusCode().value());
        assertEquals(200, restTemplate.getForEntity("/actuator/health/readiness", String.class)
                .getStatusCode().value());
    }
}
