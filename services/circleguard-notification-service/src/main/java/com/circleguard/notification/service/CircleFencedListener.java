package com.circleguard.notification.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Service;

import java.util.Map;

/**
 * HU-12: this listener no longer catches exceptions. A failure reaches the container's error handler
 * ({@code KafkaErrorHandlingConfig}), which retries transient errors and publishes what cannot be processed to
 * {@code circle.fenced.DLT} instead of silently dropping the event.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class CircleFencedListener {

    private final ObjectMapper objectMapper;
    private final RoomReservationService roomReservationService;

    @KafkaListener(topics = "circle.fenced", groupId = "notification-group")
    public void handleCircleFenced(String message) throws JsonProcessingException {
        log.info("Received circle.fenced event: {}", message);
        Map<String, Object> payload = objectMapper.readValue(message, new TypeReference<Map<String, Object>>() {});
        String circleId = (String) payload.get("circleId");
        String locationId = (String) payload.get("locationId");

        if (locationId != null && !locationId.isEmpty()) {
            roomReservationService.cancelReservation(circleId, locationId);
        } else {
            log.warn("Circle {} has no locationId. Skipping room cancellation.", circleId);
        }
    }
}
