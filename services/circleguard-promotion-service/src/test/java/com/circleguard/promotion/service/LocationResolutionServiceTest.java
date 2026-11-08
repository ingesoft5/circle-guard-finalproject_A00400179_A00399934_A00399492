package com.circleguard.promotion.service;

import com.circleguard.promotion.model.AccessPoint;
import com.circleguard.promotion.model.Building;
import com.circleguard.promotion.model.Floor;
import com.circleguard.promotion.repository.jpa.AccessPointRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.core.SetOperations;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.kafka.core.KafkaTemplate;

import java.time.Duration;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class LocationResolutionServiceTest {

    @Mock
    private AccessPointRepository accessPointRepository;
    @Mock
    private MacSessionRegistry sessionRegistry;
    @Mock
    private GraphService graphService;
    @Mock
    private KafkaTemplate<String, Object> kafkaTemplate;
    @Mock
    private StringRedisTemplate redisTemplate;
    @Mock
    private SetOperations<String, String> setOperations;

    @InjectMocks
    private LocationResolutionService service;

    private AccessPoint accessPoint;

    @BeforeEach
    void setUp() {
        Building building = Building.builder().id(UUID.randomUUID()).name("Main").code("M").build();
        Floor floor = Floor.builder().id(UUID.randomUUID()).floorNumber(2).building(building).build();
        accessPoint = AccessPoint.builder().id(UUID.randomUUID()).macAddress("ap:01").floor(floor)
                .coordinateX(1.0).coordinateY(2.0).name("AP-1").build();
    }

    @Test
    void processSignal_UnknownAccessPoint_IsIgnored() {
        when(accessPointRepository.findByMacAddress("ap:99")).thenReturn(Optional.empty());

        service.processSignal("ap:99", "dev:01", -50.0);

        verifyNoInteractions(sessionRegistry, graphService, kafkaTemplate);
    }

    @Test
    void processSignal_UnmappedDevice_IsIgnored() {
        when(accessPointRepository.findByMacAddress("ap:01")).thenReturn(Optional.of(accessPoint));
        when(sessionRegistry.getAnonymousId("dev:01")).thenReturn(null);

        service.processSignal("ap:01", "dev:01", -50.0);

        verify(kafkaTemplate, never()).send(anyString(), anyString(), any());
        verifyNoInteractions(graphService);
    }

    @Test
    @SuppressWarnings("unchecked")
    void processSignal_PublishesAnAnonymousProximityEvent() {
        when(accessPointRepository.findByMacAddress("ap:01")).thenReturn(Optional.of(accessPoint));
        when(sessionRegistry.getAnonymousId("dev:01")).thenReturn("anon-1");
        when(redisTemplate.opsForSet()).thenReturn(setOperations);
        when(setOperations.members(anyString())).thenReturn(Set.of());

        service.processSignal("ap:01", "dev:01", -61.5);

        ArgumentCaptor<Object> event = ArgumentCaptor.forClass(Object.class);
        verify(kafkaTemplate).send(eq("proximity.detected"), eq("anon-1"), event.capture());
        Map<String, Object> payload = (Map<String, Object>) event.getValue();
        assertThat(payload).containsEntry("anonymousId", "anon-1").containsEntry("rssi", -61.5);
        assertThat(payload).containsKeys("buildingId", "floorId", "coordinates", "timestamp");
        assertThat(payload).doesNotContainKey("deviceMac");
    }

    @Test
    void processSignal_RecordsAnEncounterWithEveryOtherUserAtTheLocation() {
        when(accessPointRepository.findByMacAddress("ap:01")).thenReturn(Optional.of(accessPoint));
        when(sessionRegistry.getAnonymousId("dev:01")).thenReturn("anon-1");
        when(redisTemplate.opsForSet()).thenReturn(setOperations);
        when(setOperations.members(anyString())).thenReturn(Set.of("anon-1", "anon-2", "anon-3"));
        String locationId = accessPoint.getId().toString();

        service.processSignal("ap:01", "dev:01", -40.0);

        verify(graphService).recordEncounter("anon-1", "anon-2", locationId);
        verify(graphService).recordEncounter("anon-1", "anon-3", locationId);
        verify(graphService, never()).recordEncounter(eq("anon-1"), eq("anon-1"), anyString());
        verify(graphService).detectAndFormCircles(locationId);
    }

    @Test
    void processSignal_RegistersTheUserAtTheLocationForTenMinutes() {
        when(accessPointRepository.findByMacAddress("ap:01")).thenReturn(Optional.of(accessPoint));
        when(sessionRegistry.getAnonymousId("dev:01")).thenReturn("anon-1");
        when(redisTemplate.opsForSet()).thenReturn(setOperations);
        when(setOperations.members(anyString())).thenReturn(null);
        String key = "spatial:location:" + accessPoint.getId();

        service.processSignal("ap:01", "dev:01", -40.0);

        verify(setOperations).add(key, "anon-1");
        verify(redisTemplate).expire(key, Duration.ofMinutes(10));
        verify(graphService, never()).recordEncounter(anyString(), anyString(), anyString());
    }
}
