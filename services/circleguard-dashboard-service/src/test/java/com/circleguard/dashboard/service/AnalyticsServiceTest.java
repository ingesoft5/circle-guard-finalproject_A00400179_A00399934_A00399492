package com.circleguard.dashboard.service;

import com.circleguard.dashboard.client.PromotionClient;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** HU-15 (quality finding): the dashboard service had two tests and 2.7 % line coverage. */
@ExtendWith(MockitoExtension.class)
class AnalyticsServiceTest {

    @Mock
    private JdbcTemplate jdbc;
    @Mock
    private PromotionClient promotionClient;

    private final KAnonymityFilter filter = new KAnonymityFilter();
    private AnalyticsService service;

    @BeforeEach
    void setUp() {
        service = new AnalyticsService(jdbc, promotionClient, filter);
    }

    @Test
    void getCampusSummary_DelegatesToThePromotionService() {
        Map<String, Object> stats = Map.of("totalUsers", 1500);
        when(promotionClient.getHealthStats()).thenReturn(stats);

        assertThat(service.getCampusSummary()).isSameAs(stats);
    }

    @Test
    void getGlobalHealthStats_IsTheCampusSummary() {
        Map<String, Object> stats = Map.of("totalUsers", 1500);
        when(promotionClient.getHealthStats()).thenReturn(stats);

        assertThat(service.getGlobalHealthStats()).isEqualTo(stats);
    }

    @Test
    void getDepartmentStats_AppliesKAnonymityToTheRemoteStats() {
        when(promotionClient.getHealthStatsByDepartment("Law")).thenReturn(Map.of("department", "Law", "totalUsers", 3, "suspectCount", 1));

        Map<String, Object> result = service.getDepartmentStats("Law");

        assertThat(result).containsEntry("totalUsers", "<5").containsEntry("note", "Insufficient data for privacy");
    }

    @Test
    void getEntryTrends_MasksHoursWithFewerThanFiveEntries() {
        UUID location = UUID.randomUUID();
        Map<String, Object> small = new HashMap<>(Map.of("hour", "08:00", "entry_count", 3L));
        Map<String, Object> large = new HashMap<>(Map.of("hour", "09:00", "entry_count", 120L));
        when(jdbc.queryForList(anyString(), eq(location))).thenReturn(new ArrayList<>(List.of(small, large)));

        List<Map<String, Object>> rows = service.getEntryTrends(location);

        assertThat(rows.get(0)).containsEntry("entry_count", "<5").containsEntry("note", "Insufficient data for privacy");
        assertThat(rows.get(1)).containsEntry("entry_count", 120L).doesNotContainKey("note");
    }

    @Test
    void getEntryTrends_CountOfExactlyFiveIsNotMasked() {
        UUID location = UUID.randomUUID();
        when(jdbc.queryForList(anyString(), eq(location))).thenReturn(new ArrayList<>(List.of(new HashMap<>(Map.of("entry_count", 5L)))));

        assertThat(service.getEntryTrends(location).get(0)).containsEntry("entry_count", 5L);
    }

    @Test
    void getEntryTrends_QueriesTheGivenLocation() {
        UUID location = UUID.randomUUID();
        when(jdbc.queryForList(anyString(), eq(location))).thenReturn(new ArrayList<>());
        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);

        service.getEntryTrends(location);

        verify(jdbc).queryForList(sql.capture(), eq(location));
        assertThat(sql.getValue()).contains("FROM entry_logs").contains("location_id = ?");
    }

    @Test
    void getTimeSeries_Hourly_TruncatesToTheHour() {
        List<Map<String, Object>> rows = List.of(Map.of("status", "ACTIVE", "total", 10L));
        when(jdbc.queryForList(anyString(), eq(24))).thenReturn(rows);
        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);

        List<Map<String, Object>> result = service.getTimeSeries("hourly", 24);

        verify(jdbc).queryForList(sql.capture(), eq(24));
        assertThat(sql.getValue()).contains("date_trunc('hour', event_time)").contains("LIMIT ?");
        assertThat(result).isSameAs(rows);
    }

    @Test
    void getTimeSeries_Daily_TruncatesToTheDay() {
        when(jdbc.queryForList(anyString(), eq(7))).thenReturn(List.of());
        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);

        service.getTimeSeries("daily", 7);

        verify(jdbc).queryForList(sql.capture(), eq(7));
        assertThat(sql.getValue()).contains("date_trunc('day', event_time)");
    }

    @Test
    void getTimeSeries_AnUnknownPeriodFallsBackToHourly() {
        when(jdbc.queryForList(anyString(), eq(5))).thenReturn(List.of());
        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);

        service.getTimeSeries("weekly", 5);

        verify(jdbc).queryForList(sql.capture(), eq(5));
        assertThat(sql.getValue()).contains("date_trunc('hour', event_time)");
    }

    @Test
    void getTimeSeries_WhenTheTableIsMissing_ReturnsDeterministicMockData() {
        when(jdbc.queryForList(anyString(), eq(2))).thenThrow(new RuntimeException("relation \"status_events\" does not exist"));

        List<Map<String, Object>> series = service.getTimeSeries("hourly", 2);

        assertThat(series).hasSize(8); // 2 hours x 4 statuses
        assertThat(series).extracting(point -> point.get("status")).containsOnly("ACTIVE", "SUSPECT", "PROBABLE", "CONFIRMED");
        assertThat(series).allSatisfy(point -> assertThat((int) point.get("total")).isGreaterThanOrEqualTo(10));
        assertThat(service.getTimeSeries("hourly", 2)).extracting(point -> point.get("total"))
                .isEqualTo(series.stream().map(point -> point.get("total")).toList());
    }

    @Test
    void getTimeSeries_MockDataIsCappedAt24Buckets() {
        when(jdbc.queryForList(anyString(), eq(1000))).thenThrow(new RuntimeException("no table"));

        assertThat(service.getTimeSeries("hourly", 1000)).hasSize(24 * 4);
    }
}
