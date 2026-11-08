package com.circleguard.promotion.service;

import com.circleguard.promotion.repository.graph.UserNodeRepository;
import com.circleguard.promotion.task.GraphCleanupTask;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Answers;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.neo4j.core.Neo4jClient;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

import java.time.Duration;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** GraphService, MacSessionRegistry and the hourly GraphCleanupTask. */
@ExtendWith(MockitoExtension.class)
class GraphAndSessionServicesTest {

    @Mock
    private UserNodeRepository userNodeRepository;
    @Mock(answer = Answers.RETURNS_DEEP_STUBS)
    private Neo4jClient neo4jClient;
    @Mock
    private StringRedisTemplate redisTemplate;
    @Mock
    private ValueOperations<String, String> valueOperations;

    // ---- GraphService ----------------------------------------------------------------------------

    @Test
    void recordEncounter_StoresItWithTheCurrentTimestamp() {
        GraphService service = new GraphService(userNodeRepository, neo4jClient);
        long before = System.currentTimeMillis();

        service.recordEncounter("a", "b", "ap-1");

        ArgumentCaptor<Long> timestamp = ArgumentCaptor.forClass(Long.class);
        verify(userNodeRepository).recordEncounter(eq("a"), eq("b"), timestamp.capture(), eq("ap-1"));
        assertThat(timestamp.getValue()).isBetween(before, System.currentTimeMillis());
    }

    @Test
    void detectAndFormCircles_RunsTheClusterQueryForTheLocation() {
        GraphService service = new GraphService(userNodeRepository, neo4jClient);

        assertThatCode(() -> service.detectAndFormCircles("ap-1")).doesNotThrowAnyException();

        ArgumentCaptor<String> query = ArgumentCaptor.forClass(String.class);
        verify(neo4jClient).query(query.capture());
        assertThat(query.getValue()).contains("MERGE (c:Circle").contains("size(users) >= 3");
    }

    // ---- MacSessionRegistry ----------------------------------------------------------------------

    @Test
    void registerSession_StoresTheLowerCaseMacForEightHours() {
        MacSessionRegistry registry = new MacSessionRegistry(redisTemplate);
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);

        registry.registerSession("AA:BB:CC", "anon-1");

        verify(valueOperations).set("session:mac:aa:bb:cc", "anon-1", Duration.ofHours(8));
    }

    @Test
    void getAnonymousId_LooksTheSessionUpByLowerCaseMac() {
        MacSessionRegistry registry = new MacSessionRegistry(redisTemplate);
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        when(valueOperations.get("session:mac:aa:bb:cc")).thenReturn("anon-1");

        assertThat(registry.getAnonymousId("AA:BB:CC")).isEqualTo("anon-1");
    }

    @Test
    void getAnonymousId_UnknownDevice_ReturnsNull() {
        MacSessionRegistry registry = new MacSessionRegistry(redisTemplate);
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);

        assertThat(registry.getAnonymousId("00:00:00")).isNull();
    }

    @Test
    void closeSession_DeletesTheKey() {
        MacSessionRegistry registry = new MacSessionRegistry(redisTemplate);

        registry.closeSession("AA:BB:CC");

        verify(redisTemplate).delete("session:mac:aa:bb:cc");
    }

    // ---- GraphCleanupTask ------------------------------------------------------------------------

    @Test
    void purgeStaleEncounters_UsesAFourteenDayThreshold() {
        GraphCleanupTask task = new GraphCleanupTask(userNodeRepository);
        when(userNodeRepository.purgeStaleEncounters(anyLong())).thenReturn(5L);
        long before = System.currentTimeMillis();

        task.purgeStaleEncounters();

        ArgumentCaptor<Long> threshold = ArgumentCaptor.forClass(Long.class);
        verify(userNodeRepository).purgeStaleEncounters(threshold.capture());
        long fourteenDays = 14L * 24 * 60 * 60 * 1000;
        assertThat(threshold.getValue()).isBetween(before - fourteenDays - 1000, System.currentTimeMillis() - fourteenDays);
    }

    @Test
    void purgeStaleEncounters_ToleratesANullCount() {
        GraphCleanupTask task = new GraphCleanupTask(userNodeRepository);
        when(userNodeRepository.purgeStaleEncounters(anyLong())).thenReturn(null);

        assertThatCode(task::purgeStaleEncounters).doesNotThrowAnyException();
    }

    @Test
    void purgeStaleEncounters_SwallowsRepositoryErrors() {
        GraphCleanupTask task = new GraphCleanupTask(userNodeRepository);
        when(userNodeRepository.purgeStaleEncounters(anyLong())).thenThrow(new IllegalStateException("neo4j down"));

        assertThatCode(task::purgeStaleEncounters).doesNotThrowAnyException();
        verify(userNodeRepository).purgeStaleEncounters(anyLong());
        org.mockito.Mockito.verifyNoMoreInteractions(userNodeRepository);
    }
}
