package com.circleguard.auth.service;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.ExpiredJwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import io.jsonwebtoken.JwtException;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.authority.SimpleGrantedAuthority;

import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class JwtTokenServiceTest {

    // Throwaway key built at run time: it is never a literal credential.
    private static final String SECRET = "k".repeat(48);

    private static Claims parse(String token, String secret) {
        return Jwts.parserBuilder()
                .setSigningKey(Keys.hmacShaKeyFor(secret.getBytes()))
                .build()
                .parseClaimsJws(token)
                .getBody();
    }

    private static Authentication authWith(String... authorities) {
        return new UsernamePasswordAuthenticationToken("user", null,
                java.util.Arrays.stream(authorities).map(SimpleGrantedAuthority::new).toList());
    }

    @Test
    void generateToken_UsesTheAnonymousIdAsSubject() {
        JwtTokenService service = new JwtTokenService(SECRET, 60_000);
        UUID anonymousId = UUID.randomUUID();

        String token = service.generateToken(anonymousId, authWith("health:read"));

        assertThat(parse(token, SECRET).getSubject()).isEqualTo(anonymousId.toString());
    }

    @Test
    void generateToken_IncludesEveryAuthorityAsPermission() {
        JwtTokenService service = new JwtTokenService(SECRET, 60_000);

        String token = service.generateToken(UUID.randomUUID(), authWith("ROLE_ADMIN", "alert:send"));

        assertThat(parse(token, SECRET).get("permissions", List.class))
                .containsExactlyInAnyOrder("ROLE_ADMIN", "alert:send");
    }

    @Test
    void generateToken_WithoutAuthorities_YieldsAnEmptyPermissionList() {
        JwtTokenService service = new JwtTokenService(SECRET, 60_000);

        String token = service.generateToken(UUID.randomUUID(), authWith());

        assertThat(parse(token, SECRET).get("permissions", List.class)).isEmpty();
    }

    @Test
    void generateToken_SetsAFutureExpiration() {
        JwtTokenService service = new JwtTokenService(SECRET, 60_000);

        Claims claims = parse(service.generateToken(UUID.randomUUID(), authWith("a")), SECRET);

        assertThat(claims.getExpiration()).isAfter(claims.getIssuedAt());
    }

    @Test
    void generateToken_WithAPastExpiration_IsRejectedWhenParsed() {
        JwtTokenService service = new JwtTokenService(SECRET, -1_000);
        String token = service.generateToken(UUID.randomUUID(), authWith("a"));

        assertThatThrownBy(() -> parse(token, SECRET)).isInstanceOf(ExpiredJwtException.class);
    }

    @Test
    void generateToken_SignedWithAnotherKey_IsRejectedWhenParsed() {
        JwtTokenService service = new JwtTokenService(SECRET, 60_000);
        String token = service.generateToken(UUID.randomUUID(), authWith("a"));

        assertThatThrownBy(() -> parse(token, "z".repeat(48))).isInstanceOf(JwtException.class);
    }
}
