package com.circleguard.dashboard.controller;

import com.circleguard.dashboard.service.AnalyticsService;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;
import java.util.Map;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** HU-15 (quality finding): the endpoints of the analytics controller that had no test. */
@WebMvcTest(AnalyticsController.class)
class AnalyticsControllerEndpointsTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private AnalyticsService analyticsService;

    @Test
    void summary_ReturnsTheCampusSummary() throws Exception {
        Mockito.when(analyticsService.getCampusSummary()).thenReturn(Map.of("totalUsers", 1500));

        mockMvc.perform(get("/api/v1/analytics/summary").accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk()).andExpect(jsonPath("$.totalUsers").value(1500));
    }

    @Test
    void department_ReturnsTheDepartmentStats() throws Exception {
        Mockito.when(analyticsService.getDepartmentStats("Law")).thenReturn(Map.of("department", "Law", "totalUsers", "<5"));

        mockMvc.perform(get("/api/v1/analytics/department/Law").accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk()).andExpect(jsonPath("$.department").value("Law")).andExpect(jsonPath("$.totalUsers").value("<5"));
    }

    @Test
    void timeSeries_UsesHourlyAnd24AsDefaults() throws Exception {
        Mockito.when(analyticsService.getTimeSeries("hourly", 24)).thenReturn(List.of(Map.of("status", "ACTIVE", "total", 210)));

        mockMvc.perform(get("/api/v1/analytics/time-series").accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk()).andExpect(jsonPath("$[0].status").value("ACTIVE")).andExpect(jsonPath("$[0].total").value(210));
    }

    @Test
    void timeSeries_PassesThePeriodAndTheLimit() throws Exception {
        Mockito.when(analyticsService.getTimeSeries("daily", 7)).thenReturn(List.of(Map.of("status", "SUSPECT", "total", 31)));

        mockMvc.perform(get("/api/v1/analytics/time-series").param("period", "daily").param("limit", "7").accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk()).andExpect(jsonPath("$[0].status").value("SUSPECT"));
    }

    @Test
    void timeSeries_ANonNumericLimitIsABadRequest() throws Exception {
        mockMvc.perform(get("/api/v1/analytics/time-series").param("limit", "many")).andExpect(status().isBadRequest());
    }

    @Test
    void trends_ANonUuidLocationIsABadRequest() throws Exception {
        mockMvc.perform(get("/api/v1/analytics/trends/not-a-uuid")).andExpect(status().isBadRequest());
    }
}
