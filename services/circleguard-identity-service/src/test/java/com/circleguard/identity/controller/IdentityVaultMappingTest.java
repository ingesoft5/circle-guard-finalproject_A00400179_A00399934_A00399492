package com.circleguard.identity.controller;

import com.circleguard.identity.config.SecurityConfig;
import com.circleguard.identity.event.IdentityAccessEvent;
import com.circleguard.identity.service.IdentityVaultService;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.web.servlet.MockMvc;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Public mapping endpoints, the audit event contents and the CORS rules of the identity service. */
@WebMvcTest(IdentityVaultController.class)
@Import(SecurityConfig.class)
class IdentityVaultMappingTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private IdentityVaultService vaultService;

    @MockBean
    private KafkaTemplate<String, Object> kafkaTemplate;

    @Test
    void mapIdentity_IsPublicAndReturnsTheAnonymousId() throws Exception {
        UUID anonymousId = UUID.randomUUID();
        when(vaultService.getOrCreateAnonymousId("alice@example.com")).thenReturn(anonymousId);

        mockMvc.perform(post("/api/v1/identities/map")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"realIdentity\":\"alice@example.com\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.anonymousId").value(anonymousId.toString()));
    }

    @Test
    void registerVisitor_CombinesTheVisitDetailsIntoOneIdentity() throws Exception {
        UUID anonymousId = UUID.randomUUID();
        when(vaultService.getOrCreateAnonymousId("VISITOR|v@example.com|Vera|Meeting")).thenReturn(anonymousId);

        mockMvc.perform(post("/api/v1/identities/visitor")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Vera\",\"email\":\"v@example.com\",\"reason_for_visit\":\"Meeting\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.anonymousId").value(anonymousId.toString()));
    }

    @Test
    @WithMockUser(username = "doctor", authorities = "identity:lookup")
    void lookup_AuditsTheAccessWithTheRequestingUser() throws Exception {
        UUID anonymousId = UUID.randomUUID();
        when(vaultService.resolveRealIdentity(anonymousId)).thenReturn("alice@example.com");

        mockMvc.perform(get("/api/v1/identities/lookup/{id}", anonymousId)).andExpect(status().isOk());

        ArgumentCaptor<Object> event = ArgumentCaptor.forClass(Object.class);
        verify(kafkaTemplate).send(eq("audit.identity.accessed"), event.capture());
        IdentityAccessEvent audit = (IdentityAccessEvent) event.getValue();
        assertThat(audit.getSource()).isEqualTo("circleguard-identity-service");
        assertThat(audit.getPayload().getAnonymousId()).isEqualTo(anonymousId);
        assertThat(audit.getPayload().getRequestingUser()).isEqualTo("doctor");
        assertThat(audit.getPayload().getAccessStatus()).isEqualTo("SUCCESS");
        assertThat(audit.getMetadata().getVersion()).isEqualTo(1);
    }

    @Test
    @WithMockUser(authorities = "identity:lookup")
    void lookup_WhenTheVaultFails_AuditsAnErrorAndPropagates() throws Exception {
        UUID anonymousId = UUID.randomUUID();
        when(vaultService.resolveRealIdentity(anonymousId)).thenThrow(new IllegalStateException("vault down"));

        assertThatThrownBy(() -> mockMvc.perform(get("/api/v1/identities/lookup/{id}", anonymousId)))
                .hasRootCauseInstanceOf(IllegalStateException.class);

        ArgumentCaptor<Object> event = ArgumentCaptor.forClass(Object.class);
        verify(kafkaTemplate).send(eq("audit.identity.accessed"), event.capture());
        assertThat(((IdentityAccessEvent) event.getValue()).getPayload().getAccessStatus()).isEqualTo("ERROR");
    }

    @Test
    void cors_AllowsTheLocalFrontendOnly() throws Exception {
        mockMvc.perform(options("/api/v1/identities/map")
                        .header("Origin", "http://localhost:8080")
                        .header("Access-Control-Request-Method", "POST"))
                .andExpect(status().isOk())
                .andExpect(header().string("Access-Control-Allow-Origin", "http://localhost:8080"));

        mockMvc.perform(options("/api/v1/identities/map")
                        .header("Origin", "http://evil.example.com")
                        .header("Access-Control-Request-Method", "POST"))
                .andExpect(status().isForbidden());
        verify(kafkaTemplate, org.mockito.Mockito.never()).send(any(String.class), any());
    }
}
