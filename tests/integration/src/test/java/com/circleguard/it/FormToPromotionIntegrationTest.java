package com.circleguard.it;

import com.circleguard.promotion.model.jpa.SystemSettings;
import com.circleguard.promotion.repository.jpa.SystemSettingsRepository;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.StringRedisTemplate;

import java.time.Duration;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;

/**
 * IT-1 and IT-2 (HU-04): form service -> Kafka -> promotion service, with real Kafka, Neo4j, Redis and Postgres.
 */
class FormToPromotionIntegrationTest {

    @BeforeAll
    static void environment() throws Exception {
        IntegrationEnvironment.start();
        SystemSettingsRepository settings = IntegrationEnvironment.promotion().getBean(SystemSettingsRepository.class);
        if (settings.count() == 0) {
            settings.save(SystemSettings.builder().unconfirmedFencingEnabled(true).autoThresholdSeconds(3600L)
                    .mandatoryFenceDays(14).encounterWindowDays(14).build());
        }
    }

    private static StringRedisTemplate redis() {
        return IntegrationEnvironment.promotion().getBean(StringRedisTemplate.class);
    }

    private static String statusOf(String id) {
        return IntegrationEnvironment.graphStatus(id);
    }

    @Test
    @DisplayName("IT-1: a survey with symptoms sent by form turns the user into SUSPECT in promotion")
    void surveyWithSymptoms_PromotesTheUserToSuspect() {
        UUID id = UUID.randomUUID();
        IntegrationEnvironment.createUser(id.toString(), "ACTIVE", null);

        IntegrationEnvironment.submitSurvey(id, true);

        await().atMost(Duration.ofSeconds(60)).untilAsserted(() -> assertThat(statusOf(id.toString())).isEqualTo("SUSPECT"));
        assertThat(redis().opsForValue().get("user:status:" + id)).isEqualTo("SUSPECT");
    }

    @Test
    @DisplayName("IT-1b: a survey without symptoms leaves the user ACTIVE")
    void surveyWithoutSymptoms_DoesNotChangeTheStatus() {
        UUID healthy = UUID.randomUUID();
        UUID sick = UUID.randomUUID();
        IntegrationEnvironment.createUser(healthy.toString(), "ACTIVE", null);
        IntegrationEnvironment.createUser(sick.toString(), "ACTIVE", null);

        IntegrationEnvironment.submitSurvey(healthy, false);
        // The later survey is processed after the first one (same partition), so waiting for it proves the first was handled.
        IntegrationEnvironment.submitSurvey(sick, true);

        await().atMost(Duration.ofSeconds(60)).untilAsserted(() -> assertThat(statusOf(sick.toString())).isEqualTo("SUSPECT"));
        assertThat(statusOf(healthy.toString())).isEqualTo("ACTIVE");
    }

    @Test
    @DisplayName("IT-2: an approved certificate sent by form restores the user to ACTIVE in promotion")
    void approvedCertificate_RestoresTheUserToActive() {
        UUID id = UUID.randomUUID();
        // Suspect since long ago, so the mandatory fence window has already elapsed.
        IntegrationEnvironment.createUser(id.toString(), "SUSPECT", 1L);

        IntegrationEnvironment.approveCertificate(id);

        await().atMost(Duration.ofSeconds(60)).untilAsserted(() -> assertThat(statusOf(id.toString())).isEqualTo("ACTIVE"));
    }
}
