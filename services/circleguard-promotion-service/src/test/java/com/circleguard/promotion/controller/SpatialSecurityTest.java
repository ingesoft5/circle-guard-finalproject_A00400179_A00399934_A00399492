package com.circleguard.promotion.controller;

import com.circleguard.promotion.model.Building;
import com.circleguard.promotion.security.SecurityConfig;
import com.circleguard.promotion.service.AccessPointService;
import com.circleguard.promotion.service.BuildingService;
import com.circleguard.promotion.service.FloorService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.web.servlet.MockMvc;

import java.util.UUID;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** The ADMIN rule of the building endpoints and the CORS configuration, with the real security setup. */
@WebMvcTest({BuildingController.class, FloorController.class, AccessPointController.class})
@Import(SecurityConfig.class)
class SpatialSecurityTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private BuildingService buildingService;
    @MockBean
    private FloorService floorService;
    @MockBean
    private AccessPointService accessPointService;

    private static final String BODY = "{\"name\":\"Main\",\"code\":\"MAIN\"}";

    @Test
    @WithMockUser(authorities = "ADMIN")
    void createBuilding_WithTheAdminAuthority_IsAllowed() throws Exception {
        when(buildingService.createBuilding(any(), any(), any(), any(), any(), any()))
                .thenReturn(Building.builder().id(UUID.randomUUID()).name("Main").code("MAIN").build());

        mockMvc.perform(post("/api/v1/buildings").contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isOk());
    }

    @Test
    @WithMockUser(authorities = "STUDENT")
    void createBuilding_WithoutTheAdminAuthority_IsForbidden() throws Exception {
        mockMvc.perform(post("/api/v1/buildings").contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isForbidden());

        verify(buildingService, never()).createBuilding(any(), any(), any(), any(), any(), any());
    }

    @Test
    void cors_AllowsTheLocalFrontendOnly() throws Exception {
        mockMvc.perform(options("/api/v1/buildings")
                        .header("Origin", "http://localhost:8080")
                        .header("Access-Control-Request-Method", "POST"))
                .andExpect(status().isOk())
                .andExpect(header().string("Access-Control-Allow-Origin", "http://localhost:8080"));

        mockMvc.perform(options("/api/v1/buildings")
                        .header("Origin", "http://evil.example.com")
                        .header("Access-Control-Request-Method", "POST"))
                .andExpect(status().isForbidden());
    }
}
