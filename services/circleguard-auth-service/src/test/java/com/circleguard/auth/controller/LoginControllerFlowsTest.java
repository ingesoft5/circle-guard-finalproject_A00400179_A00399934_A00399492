package com.circleguard.auth.controller;

import com.circleguard.auth.client.IdentityClient;
import com.circleguard.auth.security.SecurityConfig;
import com.circleguard.auth.service.CustomUserDetailsService;
import com.circleguard.auth.service.JwtTokenService;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.core.Authentication;
import org.springframework.test.web.servlet.MockMvc;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Error paths and the visitor handoff of the login controller. */
@WebMvcTest(LoginController.class)
@Import(SecurityConfig.class)
class LoginControllerFlowsTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private AuthenticationManager authManager;

    @MockBean
    private JwtTokenService jwtService;

    @MockBean
    private IdentityClient identityClient;

    @MockBean
    private CustomUserDetailsService userDetailsService;

    private static final String LOGIN = "{\"username\": \"alice\", \"password\": \"wrong\"}";

    @Test
    void login_WithBadCredentials_Returns401AndNoToken() throws Exception {
        when(authManager.authenticate(any())).thenThrow(new BadCredentialsException("bad"));

        mockMvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON).content(LOGIN))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.message").value("Invalid username or password"))
                .andExpect(jsonPath("$.token").doesNotExist());
    }

    @Test
    void login_WhenTheIdentityServiceFails_Returns500() throws Exception {
        when(authManager.authenticate(any())).thenReturn(mock(Authentication.class));
        when(identityClient.getAnonymousId("alice")).thenThrow(new IllegalStateException("identity down"));

        mockMvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON).content(LOGIN))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.message").value("Internal server error: identity down"));
    }

    @Test
    void visitorHandoff_IssuesATokenWithTheVisitorAuthority() throws Exception {
        UUID anonymousId = UUID.randomUUID();
        when(jwtService.generateToken(any(), any())).thenReturn("visitor-jwt");

        mockMvc.perform(post("/api/v1/auth/visitor/handoff")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"anonymousId\": \"" + anonymousId + "\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.token").value("visitor-jwt"))
                .andExpect(jsonPath("$.handoffPayload").value("HANDOFF_TOKEN:" + anonymousId + ":visitor-jwt"));

        ArgumentCaptor<Authentication> captor = ArgumentCaptor.forClass(Authentication.class);
        verify(jwtService).generateToken(any(), captor.capture());
        assertThat(captor.getValue().getAuthorities()).extracting("authority").containsExactly("VISITOR");
    }

    @Test
    void visitorHandoff_WithoutAnAnonymousId_Returns400() throws Exception {
        mockMvc.perform(post("/api/v1/auth/visitor/handoff")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isBadRequest());
    }
}
