package com.circleguard.auth.controller;

import com.circleguard.auth.service.QrTokenService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.UUID;

import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@ExtendWith(MockitoExtension.class)
class QrTokenControllerTest {

    @Mock
    private QrTokenService qrService;

    @InjectMocks
    private QrTokenController controller;

    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.standaloneSetup(controller).build();
    }

    @Test
    void generate_ReturnsAQrTokenForTheAuthenticatedUser() throws Exception {
        UUID anonymousId = UUID.randomUUID();
        when(qrService.generateQrToken(anonymousId)).thenReturn("qr-token");

        mockMvc.perform(get("/api/v1/auth/qr/generate")
                        .principal(new UsernamePasswordAuthenticationToken(anonymousId.toString(), null)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.qrToken").value("qr-token"))
                .andExpect(jsonPath("$.expiresIn").value("60"));

        verify(qrService).generateQrToken(anonymousId);
    }
}
