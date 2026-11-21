package com.circleguard.notification.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
@Slf4j
public class ExposureNotificationListener {

    private final NotificationDispatcher dispatcher;
    private final ObjectMapper objectMapper;
    private final LmsService lmsService;

    /**
     * Listens for status changes and exposure events.
     *
     * <p>HU-12: no exception is swallowed here. A failure reaches the container's error handler
     * ({@code KafkaErrorHandlingConfig}), which retries transient errors and publishes what cannot be
     * processed to {@code promotion.status.changed.DLT}.
     */
    @KafkaListener(topics = "promotion.status.changed", groupId = "notification-group")
    public void handleStatusChange(String eventJson) throws JsonProcessingException {
        log.info("Received health status change event: {}", eventJson);
        JsonNode node = objectMapper.readTree(eventJson);
        String userId = node.path("anonymousId").asText("unknown");
        String status = node.path("status").asText("UNKNOWN");

        if (!"ACTIVE".equals(status) && !"UNKNOWN".equals(status)) {
            dispatcher.dispatch(userId, status);
            lmsService.syncRemoteAttendance(userId, status);
        }
    }
}
