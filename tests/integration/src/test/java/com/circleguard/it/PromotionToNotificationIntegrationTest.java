package com.circleguard.it;

import com.circleguard.promotion.service.HealthStatusService;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * IT-3 and IT-4 (HU-04): promotion -> Kafka -> notification, and the whole chain starting in the form service.
 * The notification service dispatches by SMS and push in its mock mode and publishes one audit event per delivery
 * on notification.audit, which is what these tests read.
 */
class PromotionToNotificationIntegrationTest {

    @BeforeAll
    static void environment() throws Exception {
        IntegrationEnvironment.start();
    }

    private static boolean delivered(String json, UUID user, String channel) {
        return json.contains(user.toString()) && json.contains("\"channel\":\"" + channel + "\"") && json.contains("\"status\":\"SUCCESS\"");
    }

    @Test
    @DisplayName("IT-3: a status change published by promotion is notified by SMS and push")
    void statusChange_IsDispatchedByTheNotificationService() {
        UUID id = UUID.randomUUID();
        IntegrationEnvironment.createUser(id.toString(), "ACTIVE", null);

        IntegrationEnvironment.promotion().getBean(HealthStatusService.class).updateStatus(id.toString(), "CONFIRMED");

        List<String> sms = KafkaProbe.read("notification.audit", json -> delivered(json, id, "SMS"), Duration.ofSeconds(60));
        List<String> push = KafkaProbe.read("notification.audit", json -> delivered(json, id, "PUSH"), Duration.ofSeconds(60));
        assertThat(sms).as("SMS audit event").isNotEmpty();
        assertThat(push).as("push audit event").isNotEmpty();
    }

    @Test
    @DisplayName("IT-4: survey (form) -> SUSPECT (promotion) -> notification of the user")
    void surveyWithSymptoms_EndsInANotification() {
        UUID id = UUID.randomUUID();
        IntegrationEnvironment.createUser(id.toString(), "ACTIVE", null);

        IntegrationEnvironment.submitSurvey(id, true);

        List<String> sms = KafkaProbe.read("notification.audit", json -> delivered(json, id, "SMS"), Duration.ofSeconds(90));
        assertThat(sms).as("SMS audit event of the whole chain").isNotEmpty();
    }
}
