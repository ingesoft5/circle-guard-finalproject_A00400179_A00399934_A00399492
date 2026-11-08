package com.circleguard.gateway.service;

import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Date;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/** Invalid tokens and the other denied statuses of the QR validation. */
class QrValidationEdgeCasesTest {

    private static final String SECRET = "g".repeat(48);

    private final StringRedisTemplate redisTemplate = mock(StringRedisTemplate.class);
    @SuppressWarnings("unchecked")
    private final ValueOperations<String, String> valueOps = mock(ValueOperations.class);
    private QrValidationService service;

    @BeforeEach
    void setUp() {
        when(redisTemplate.opsForValue()).thenReturn(valueOps);
        service = new QrValidationService(redisTemplate);
        ReflectionTestUtils.setField(service, "qrSecret", SECRET);
    }

    private static String token(String subject, String secret, long ttlMillis) {
        return Jwts.builder()
                .setSubject(subject)
                .setExpiration(new Date(System.currentTimeMillis() + ttlMillis))
                .signWith(Keys.hmacShaKeyFor(secret.getBytes()), SignatureAlgorithm.HS256)
                .compact();
    }

    @Test
    void validToken_OfAUserWithNoStoredStatus_IsAllowed() {
        String id = UUID.randomUUID().toString();
        when(valueOps.get("user:status:" + id)).thenReturn(null);

        QrValidationService.ValidationResult result = service.validateToken(token(id, SECRET, 60_000));

        assertThat(result.valid()).isTrue();
        assertThat(result.status()).isEqualTo("GREEN");
        assertThat(result.message()).isEqualTo("Welcome to Campus");
    }

    @Test
    void potentialStatus_IsDeniedForHealthRisk() {
        String id = UUID.randomUUID().toString();
        when(valueOps.get("user:status:" + id)).thenReturn("POTENTIAL");

        QrValidationService.ValidationResult result = service.validateToken(token(id, SECRET, 60_000));

        assertThat(result.valid()).isFalse();
        assertThat(result.message()).isEqualTo("Access Denied: Health Risk Detected");
    }

    @Test
    void expiredToken_IsRejected() {
        QrValidationService.ValidationResult result = service.validateToken(token("anon", SECRET, -60_000));

        assertThat(result.valid()).isFalse();
        assertThat(result.message()).isEqualTo("Invalid or Expired Token");
    }

    @Test
    void tokenSignedWithAnotherKey_IsRejected() {
        QrValidationService.ValidationResult result = service.validateToken(token("anon", "h".repeat(48), 60_000));

        assertThat(result.valid()).isFalse();
        assertThat(result.status()).isEqualTo("RED");
    }

    @Test
    void malformedOrMissingToken_IsRejected() {
        assertThat(service.validateToken("not-a-jwt").valid()).isFalse();
        assertThat(service.validateToken(null).valid()).isFalse();
        assertThat(service.validateToken("").message()).isEqualTo("Invalid or Expired Token");
    }
}
