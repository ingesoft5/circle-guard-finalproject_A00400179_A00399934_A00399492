package com.circleguard.gateway.controller;

import com.circleguard.gateway.service.QrValidationService;
import com.circleguard.gateway.service.QrValidationService.ValidationResult;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@ExtendWith(MockitoExtension.class)
class GateControllerFlowsTest {

    @Mock
    private QrValidationService validationService;

    @InjectMocks
    private GateController controller;

    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.standaloneSetup(controller).build();
    }

    @Test
    void validate_ReturnsTheGreenResultOfAValidToken() throws Exception {
        when(validationService.validateToken("good")).thenReturn(new ValidationResult(true, "GREEN", "Welcome to Campus"));

        mockMvc.perform(post("/api/v1/gate/validate").contentType(MediaType.APPLICATION_JSON).content("{\"token\":\"good\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.valid").value(true))
                .andExpect(jsonPath("$.status").value("GREEN"))
                .andExpect(jsonPath("$.message").value("Welcome to Campus"));
    }

    @Test
    void validate_ReturnsTheRedResultOfADeniedToken() throws Exception {
        when(validationService.validateToken("bad")).thenReturn(new ValidationResult(false, "RED", "Access Denied: Health Risk Detected"));

        mockMvc.perform(post("/api/v1/gate/validate").contentType(MediaType.APPLICATION_JSON).content("{\"token\":\"bad\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.valid").value(false))
                .andExpect(jsonPath("$.status").value("RED"));
    }

    @Test
    void validate_WithoutAToken_AsksTheServiceWithNull() throws Exception {
        when(validationService.validateToken(null)).thenReturn(new ValidationResult(false, "RED", "Invalid or Expired Token"));

        mockMvc.perform(post("/api/v1/gate/validate").contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("Invalid or Expired Token"));

        verify(validationService).validateToken(null);
    }
}
