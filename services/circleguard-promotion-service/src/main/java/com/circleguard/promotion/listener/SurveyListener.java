package com.circleguard.promotion.listener;

import com.circleguard.promotion.service.HealthStatusService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;
import java.util.Map;

/**
 * Consumers of the form-service events.
 *
 * <p>HU-12: these methods no longer catch exceptions. A failure reaches the container's error handler
 * ({@code KafkaErrorHandlingConfig}), which retries transient errors and publishes what cannot be processed
 * to the {@code <topic>.DLT} dead letter topic, instead of silently dropping the event.
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class SurveyListener {
    private final HealthStatusService healthStatusService;

    @KafkaListener(topics = "survey.submitted", groupId = "promotion-service-group")
    public void onSurveySubmitted(Map<String, Object> event) {
        log.info("Received survey submission event: {}", event);

        String anonymousId = (String) event.get("anonymousId");
        Boolean hasSymptoms = (Boolean) event.get("hasSymptoms");

        if (anonymousId != null && Boolean.TRUE.equals(hasSymptoms)) {
            log.info("Promoting user {} to SUSPECT due to symptoms", anonymousId);
            healthStatusService.updateStatus(anonymousId, "SUSPECT");
        }
    }

    @KafkaListener(topics = "certificate.validated", groupId = "promotion-service-group")
    public void onCertificateValidated(Map<String, Object> event) {
        log.info("Received certificate validation event: {}", event);

        String anonymousId = (String) event.get("anonymousId");
        String status = (String) event.get("status");

        if (anonymousId != null && "APPROVED".equals(status)) {
            log.info("Restoring user {} to ACTIVE due to approved certificate", anonymousId);
            healthStatusService.updateStatus(anonymousId, "ACTIVE");
        }
    }
}
