package com.circleguard.dashboard.client;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestTemplate;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

/** HU-15 (quality finding): the HTTP client of the dashboard towards promotion-service, tested without a network. */
class PromotionClientTest {

    private static final String BASE = "http://promotion.test:8088";
    private MockRestServiceServer server;
    private PromotionClient client;

    @BeforeEach
    void setUp() {
        RestTemplate restTemplate = new RestTemplate();
        server = MockRestServiceServer.createServer(restTemplate);
        RestTemplateBuilder builder = mock(RestTemplateBuilder.class);
        when(builder.build()).thenReturn(restTemplate);
        client = new PromotionClient(builder, BASE);
    }

    @Test
    void getHealthStats_ReturnsTheRemoteStats() {
        server.expect(requestTo(BASE + "/api/v1/health-status/stats")).andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess("{\"totalUsers\":1500,\"suspectCount\":12}", MediaType.APPLICATION_JSON));

        Map<String, Object> stats = client.getHealthStats();

        assertThat(stats).containsEntry("totalUsers", 1500).containsEntry("suspectCount", 12);
        server.verify();
    }

    @Test
    void getHealthStats_WhenThePromotionServiceFails_ReturnsAnErrorMapInsteadOfThrowing() {
        server.expect(requestTo(BASE + "/api/v1/health-status/stats")).andRespond(withStatus(HttpStatus.SERVICE_UNAVAILABLE));

        Map<String, Object> stats = client.getHealthStats();

        assertThat(stats).containsEntry("error", "Service unavailable").containsKey("timestamp");
    }

    @Test
    void getHealthStatsByDepartment_CallsTheDepartmentEndpoint() {
        server.expect(requestTo(BASE + "/api/v1/health-status/stats/department/Law"))
                .andRespond(withSuccess("{\"department\":\"Law\",\"totalUsers\":40}", MediaType.APPLICATION_JSON));

        assertThat(client.getHealthStatsByDepartment("Law")).containsEntry("department", "Law").containsEntry("totalUsers", 40);
        server.verify();
    }

    @Test
    void getHealthStatsByDepartment_OnFailure_KeepsTheDepartmentInTheErrorMap() {
        server.expect(requestTo(BASE + "/api/v1/health-status/stats/department/Law")).andRespond(withStatus(HttpStatus.INTERNAL_SERVER_ERROR));

        assertThat(client.getHealthStatsByDepartment("Law")).containsEntry("error", "Service unavailable").containsEntry("department", "Law");
    }
}
