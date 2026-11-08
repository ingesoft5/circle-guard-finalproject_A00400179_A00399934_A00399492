package com.circleguard.auth.service;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.ExpiredJwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class QrTokenServiceTest {

    private static final String SECRET = "q".repeat(48);

    private static Claims parse(String token) {
        return Jwts.parserBuilder()
                .setSigningKey(Keys.hmacShaKeyFor(SECRET.getBytes()))
                .build()
                .parseClaimsJws(token)
                .getBody();
    }

    @Test
    void generateQrToken_CarriesTheAnonymousIdAsSubject() {
        QrTokenService service = new QrTokenService(SECRET, 60_000);
        UUID anonymousId = UUID.randomUUID();

        assertThat(parse(service.generateQrToken(anonymousId)).getSubject()).isEqualTo(anonymousId.toString());
    }

    @Test
    void generateQrToken_ExpiresAfterTheConfiguredTime() {
        QrTokenService service = new QrTokenService(SECRET, 60_000);

        Claims claims = parse(service.generateQrToken(UUID.randomUUID()));

        long lifetime = claims.getExpiration().getTime() - claims.getIssuedAt().getTime();
        assertThat(lifetime).isBetween(59_000L, 61_000L);
    }

    @Test
    void generateQrToken_WithAPastExpiration_IsRejectedWhenParsed() {
        QrTokenService service = new QrTokenService(SECRET, -1_000);
        String token = service.generateQrToken(UUID.randomUUID());

        assertThatThrownBy(() -> parse(token)).isInstanceOf(ExpiredJwtException.class);
    }

    @Test
    void generateQrToken_ProducesADifferentTokenForEachUser() {
        QrTokenService service = new QrTokenService(SECRET, 60_000);

        assertThat(service.generateQrToken(UUID.randomUUID()))
                .isNotEqualTo(service.generateQrToken(UUID.randomUUID()));
    }
}
