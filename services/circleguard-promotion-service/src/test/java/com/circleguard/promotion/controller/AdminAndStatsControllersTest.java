package com.circleguard.promotion.controller;

import com.circleguard.promotion.model.jpa.SystemSettings;
import com.circleguard.promotion.repository.jpa.SystemSettingsRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Answers;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.neo4j.core.Neo4jClient;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@ExtendWith(MockitoExtension.class)
class AdminAndStatsControllersTest {

    @Mock
    private SystemSettingsRepository settingsRepository;
    @Mock(answer = Answers.RETURNS_DEEP_STUBS)
    private Neo4jClient neo4jClient;

    private MockMvc admin;
    private MockMvc stats;

    @BeforeEach
    void setUp() {
        admin = MockMvcBuilders.standaloneSetup(new AdminController(settingsRepository)).build();
        stats = MockMvcBuilders.standaloneSetup(new HealthStatsController(neo4jClient)).build();
    }

    private static SystemSettings settings() {
        return SystemSettings.builder().id(1L).unconfirmedFencingEnabled(true).autoThresholdSeconds(3600L)
                .mandatoryFenceDays(14).encounterWindowDays(14).build();
    }

    // ---- AdminController -------------------------------------------------------------------------

    @Test
    void getSettings_ReturnsTheStoredSettings() throws Exception {
        when(settingsRepository.getSettings()).thenReturn(Optional.of(settings()));

        admin.perform(get("/api/v1/admin/settings"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.mandatoryFenceDays").value(14))
                .andExpect(jsonPath("$.autoThresholdSeconds").value(3600));
    }

    @Test
    void getSettings_WhenNoneExist_CreatesTheDefaults() throws Exception {
        when(settingsRepository.getSettings()).thenReturn(Optional.empty());
        when(settingsRepository.save(any(SystemSettings.class))).thenAnswer(i -> i.getArgument(0));

        admin.perform(get("/api/v1/admin/settings"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.unconfirmedFencingEnabled").value(true))
                .andExpect(jsonPath("$.encounterWindowDays").value(14));
    }

    @Test
    void updateSettings_ChangesOnlyTheFieldsThatAreSent() throws Exception {
        SystemSettings stored = settings();
        when(settingsRepository.getSettings()).thenReturn(Optional.of(stored));

        admin.perform(post("/api/v1/admin/settings").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"mandatoryFenceDays\":7}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.mandatoryFenceDays").value(7))
                .andExpect(jsonPath("$.encounterWindowDays").value(14));

        verify(settingsRepository).save(stored);
    }

    @Test
    void updateSettings_CanChangeEveryField() throws Exception {
        SystemSettings stored = settings();
        when(settingsRepository.getSettings()).thenReturn(Optional.of(stored));

        admin.perform(post("/api/v1/admin/settings").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"unconfirmedFencingEnabled\":false,\"autoThresholdSeconds\":60,\"mandatoryFenceDays\":3,\"encounterWindowDays\":5}"))
                .andExpect(status().isOk());

        assertThat(stored.getUnconfirmedFencingEnabled()).isFalse();
        assertThat(stored.getAutoThresholdSeconds()).isEqualTo(60L);
        assertThat(stored.getMandatoryFenceDays()).isEqualTo(3);
        assertThat(stored.getEncounterWindowDays()).isEqualTo(5);
    }

    @Test
    void toggleUnconfirmedFencing_SetsTheFlag() throws Exception {
        SystemSettings stored = settings();
        when(settingsRepository.getSettings()).thenReturn(Optional.of(stored));

        admin.perform(post("/api/v1/admin/settings/toggle-unconfirmed-fencing").param("enabled", "false"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.unconfirmedFencingEnabled").value(false));

        verify(settingsRepository).save(stored);
    }

    // ---- HealthStatsController -------------------------------------------------------------------

    @Test
    void stats_AggregatesTheUserCountsByStatus() throws Exception {
        when(neo4jClient.query(anyString()).fetch().all()).thenReturn(List.of(
                Map.of("status", "ACTIVE", "total", 8L),
                Map.of("status", "SUSPECT", "total", 2)));

        stats.perform(get("/api/v1/health-status/stats"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.activeCount").value(8))
                .andExpect(jsonPath("$.suspectCount").value(2))
                .andExpect(jsonPath("$.totalUsers").value(10))
                .andExpect(jsonPath("$.timestamp").exists());
    }

    @Test
    void stats_UsersWithoutStatusAreCountedAsUnknown() throws Exception {
        java.util.Map<String, Object> row = new java.util.HashMap<>();
        row.put("status", null);
        row.put("total", 3L);
        when(neo4jClient.query(anyString()).fetch().all()).thenReturn(List.of(row));

        stats.perform(get("/api/v1/health-status/stats"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.unknownCount").value(3))
                .andExpect(jsonPath("$.totalUsers").value(3));
    }

    @Test
    void statsByDepartment_BindsTheDepartmentAndEchoesIt() throws Exception {
        when(neo4jClient.query(anyString()).bind(any()).to(anyString()).fetch().all()).thenReturn(List.of(
                Map.of("status", "CONFIRMED", "total", 1L)));

        stats.perform(get("/api/v1/health-status/stats/department/{d}", "Engineering"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.department").value("Engineering"))
                .andExpect(jsonPath("$.confirmedCount").value(1))
                .andExpect(jsonPath("$.totalUsers").value(1));

        ArgumentCaptor<String> query = ArgumentCaptor.forClass(String.class);
        verify(neo4jClient, org.mockito.Mockito.atLeastOnce()).query(query.capture());
        assertThat(query.getAllValues()).anyMatch(q -> q.contains("u.department = $dept"));
    }
}
