package com.circleguard.auth.client;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestTemplate;

import java.util.UUID;

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
}
