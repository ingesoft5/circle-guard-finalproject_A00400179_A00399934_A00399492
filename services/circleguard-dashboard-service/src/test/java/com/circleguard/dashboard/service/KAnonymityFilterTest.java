package com.circleguard.dashboard.service;

import org.junit.jupiter.api.Test;

import java.util.LinkedHashMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/** HU-15 (quality finding): the k-anonymity filter is the privacy guarantee of the dashboard and had no tests. */
class KAnonymityFilterTest {

    private final KAnonymityFilter filter = new KAnonymityFilter();

    private static Map<String, Object> stats(Object totalUsers, Object suspectCount, Object confirmedCount) {
        Map<String, Object> stats = new LinkedHashMap<>();
        stats.put("department", "Engineering");
        stats.put("timestamp", "2026-11-20T10:00:00Z");
        stats.put("totalUsers", totalUsers);
        stats.put("suspectCount", suspectCount);
        stats.put("confirmedCount", confirmedCount);
        return stats;
    }

    @Test
    void apply_NullStats_ReturnsAnEmptyMap() {
        assertThat(filter.apply(null)).isEmpty();
    }

    @Test
    void apply_PopulationBelowK_MasksTheWholeResult() {
        Map<String, Object> result = filter.apply(stats(3, 2, 1));

        assertThat(result).containsEntry("note", "Insufficient data for privacy")
                .containsEntry("totalUsers", "<5")
                .containsEntry("department", "Engineering")
                .containsEntry("timestamp", "2026-11-20T10:00:00Z")
                .doesNotContainKeys("suspectCount", "confirmedCount");
    }

    @Test
    void apply_PopulationBelowK_WithoutDepartmentOrTimestamp_OnlyKeepsTheNoteAndTotal() {
        Map<String, Object> result = filter.apply(Map.of("totalUsers", 2, "suspectCount", 1));

        assertThat(result).containsOnlyKeys("note", "totalUsers");
    }

    @Test
    void apply_PopulationExactlyK_IsNotMaskedAsAWhole() {
        Map<String, Object> result = filter.apply(stats(5, 20, 30));

        assertThat(result).doesNotContainKey("note").containsEntry("totalUsers", 5);
    }

    @Test
    void apply_CountsBelowK_AreMaskedIndividually() {
        Map<String, Object> result = filter.apply(stats(100, 3, 40));

        assertThat(result).containsEntry("suspectCount", "<5").containsEntry("confirmedCount", 40);
    }

    @Test
    void apply_ZeroCount_IsNotMasked() {
        Map<String, Object> result = filter.apply(stats(100, 0, 40));

        assertThat(result).containsEntry("suspectCount", 0);
    }

    @Test
    void apply_CountEqualToK_IsNotMasked() {
        assertThat(filter.apply(stats(100, 5, 40))).containsEntry("suspectCount", 5);
    }

    @Test
    void apply_UsesTheGivenK() {
        Map<String, Object> result = filter.apply(stats(100, 8, 40), 10);

        assertThat(result).containsEntry("suspectCount", "<10").containsEntry("confirmedCount", 40);
    }

    @Test
    void apply_OnlyFieldsEndingInCountAreCandidates() {
        Map<String, Object> input = new LinkedHashMap<>();
        input.put("totalUsers", 100);
        input.put("exposedTotal", 2);
        input.put("label", "x");
        input.put("flagCount", "not-a-number");

        Map<String, Object> result = filter.apply(input);

        assertThat(result).containsEntry("exposedTotal", 2).containsEntry("label", "x").containsEntry("flagCount", "not-a-number");
    }

    @Test
    void apply_DoesNotModifyTheInput() {
        Map<String, Object> input = stats(100, 3, 40);

        filter.apply(input);

        assertThat(input).containsEntry("suspectCount", 3);
    }

    @Test
    void apply_WithoutTotalUsers_StillMasksSmallCounts() {
        Map<String, Object> result = filter.apply(Map.of("suspectCount", 2));

        assertThat(result).containsEntry("suspectCount", "<5");
    }
}
