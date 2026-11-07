package com.circleguard.promotion.config;

import com.circleguard.promotion.exception.FenceException;
import com.circleguard.promotion.model.jpa.SystemSettings;
import com.circleguard.promotion.repository.jpa.SystemSettingsRepository;
import com.circleguard.promotion.security.JwtAuthenticationFilter;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;
import io.jsonwebtoken.security.Keys;
import jakarta.persistence.EntityManagerFactory;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.mockito.Answers;
import org.neo4j.driver.Driver;
import org.springframework.cache.CacheManager;
import org.springframework.data.neo4j.core.Neo4jClient;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.orm.jpa.JpaTransactionManager;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.Date;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.CALLS_REAL_METHODS;
import static org.mockito.Mockito.doReturn;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

/** Configuration beans, the fence exception, the settings singleton lookup and the JWT filter of promotion. */
class ConfigAndSecurityBeansTest {

    private static final String SECRET = "p".repeat(48);

    @AfterEach
    void clearContext() {
        SecurityContextHolder.clearContext();
    }

    // ---- configuration ---------------------------------------------------------------------------

    @Test
    void cacheManager_DefinesTheFourCachesOfTheService() {
        CacheManager manager = new CacheConfig().cacheManager();

        assertThat(manager.getCacheNames())
                .containsExactlyInAnyOrder("userStatus", "proximityMatches", "buildingMetadata", "systemSettings");
    }

    @Test
    void jpaTransactionManager_IsBuiltOnTheEntityManagerFactory() {
        EntityManagerFactory factory = mock(EntityManagerFactory.class);

        assertThat(new JpaConfig().transactionManager(factory)).isInstanceOf(JpaTransactionManager.class);
    }

    @Test
    void neo4jTransactionManager_IsBuiltOnTheDriver() {
        assertThat(new Neo4jConfig().transactionManager(mock(Driver.class)))
                .isInstanceOf(org.springframework.data.neo4j.core.transaction.Neo4jTransactionManager.class);
    }

    @Test
    void neo4jSchema_CreatesTheFiveIndexesAndRegistersTheMembershipType() {
        Neo4jClient client = mock(Neo4jClient.class, Answers.RETURNS_DEEP_STUBS);

        new Neo4jSchemaConfig(client).initializeSchema();

        verify(client, times(6)).query(anyString());
        verify(client).query(org.mockito.ArgumentMatchers.contains("user_anon_id_idx"));
        verify(client).query(org.mockito.ArgumentMatchers.contains("circle_loc_idx"));
    }

    // ---- fence exception and settings -------------------------------------------------------------

    @Test
    void fenceException_CarriesItsMessage() {
        assertThat(new FenceException("fenced for 3 more days")).hasMessage("fenced for 3 more days");
    }

    @Test
    void getSettings_ReturnsTheFirstStoredRowOrNothing() {
        SystemSettingsRepository repository = mock(SystemSettingsRepository.class, CALLS_REAL_METHODS);
        SystemSettings settings = SystemSettings.builder().mandatoryFenceDays(14).build();

        doReturn(List.of(settings)).when(repository).findAll();
        assertThat(repository.getSettings()).contains(settings);

        doReturn(List.of()).when(repository).findAll();
        assertThat(repository.getSettings()).isEqualTo(Optional.empty());
    }

    // ---- JWT filter ------------------------------------------------------------------------------

    private static String token(Map<String, Object> claims, String secret, long ttlMillis) {
        return Jwts.builder()
                .setClaims(claims)
                .setSubject("anon-1")
                .setExpiration(new Date(System.currentTimeMillis() + ttlMillis))
                .signWith(Keys.hmacShaKeyFor(secret.getBytes()), SignatureAlgorithm.HS256)
                .compact();
    }

    private static void filter(String authorization) throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest();
        if (authorization != null) {
            request.addHeader("Authorization", authorization);
        }
        new JwtAuthenticationFilter(SECRET).doFilter(request, new MockHttpServletResponse(), new MockFilterChain());
    }

    @Test
    void jwtFilter_ValidToken_AuthenticatesWithItsPermissions() throws Exception {
        filter("Bearer " + token(Map.of("permissions", List.of("ROLE_HEALTH_CENTER", "ADMIN")), SECRET, 60_000));

        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        assertThat(auth.getName()).isEqualTo("anon-1");
        assertThat(auth.getAuthorities().stream().map(GrantedAuthority::getAuthority))
                .containsExactlyInAnyOrder("ROLE_HEALTH_CENTER", "ADMIN");
    }

    @Test
    void jwtFilter_TokenWithoutPermissions_DoesNotAuthenticate() throws Exception {
        filter("Bearer " + token(Map.of(), SECRET, 60_000));

        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
    }

    @Test
    void jwtFilter_BadOrMissingCredentials_LeaveTheRequestAnonymous() throws Exception {
        filter("Bearer " + token(Map.of("permissions", List.of("x")), "q".repeat(48), 60_000));
        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();

        filter("Bearer " + token(Map.of("permissions", List.of("x")), SECRET, -60_000));
        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();

        filter("Bearer garbage");
        filter("Basic dXNlcjpwYXNz");
        filter(null);
        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
    }
}
