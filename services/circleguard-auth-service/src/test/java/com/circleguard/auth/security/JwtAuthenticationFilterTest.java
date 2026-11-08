package com.circleguard.auth.security;

import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.Date;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class JwtAuthenticationFilterTest {

    private static final String SECRET = "f".repeat(48);

    private final JwtAuthenticationFilter filter = new JwtAuthenticationFilter(SECRET);

    @AfterEach
    void clearContext() {
        SecurityContextHolder.clearContext();
    }

    private static String token(String subject, Map<String, Object> claims, String secret, long ttlMillis) {
        return Jwts.builder()
                .setClaims(claims)
                .setSubject(subject)
                .setIssuedAt(new Date())
                .setExpiration(new Date(System.currentTimeMillis() + ttlMillis))
                .signWith(Keys.hmacShaKeyFor(secret.getBytes()), SignatureAlgorithm.HS256)
                .compact();
    }

    private MockFilterChain run(String authorizationHeader) throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest();
        if (authorizationHeader != null) {
            request.addHeader("Authorization", authorizationHeader);
        }
        MockFilterChain chain = new MockFilterChain();
        filter.doFilter(request, new MockHttpServletResponse(), chain);
        return chain;
    }

    @Test
    void validToken_SetsTheAuthenticationWithItsPermissions() throws Exception {
        String jwt = token("user-1", Map.of("permissions", List.of("health:read", "ROLE_STAFF")), SECRET, 60_000);

        run("Bearer " + jwt);

        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        assertThat(auth).isNotNull();
        assertThat(auth.getName()).isEqualTo("user-1");
        assertThat(auth.getAuthorities().stream().map(GrantedAuthority::getAuthority))
                .containsExactlyInAnyOrder("health:read", "ROLE_STAFF");
    }

    @Test
    void validTokenWithoutPermissions_AuthenticatesWithNoAuthorities() throws Exception {
        run("Bearer " + token("user-2", Map.of(), SECRET, 60_000));

        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        assertThat(auth).isNotNull();
        assertThat(auth.getAuthorities()).isEmpty();
    }

    @Test
    void tokenSignedWithAnotherKey_LeavesTheRequestAnonymous() throws Exception {
        run("Bearer " + token("user-3", Map.of(), "z".repeat(48), 60_000));

        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
    }

    @Test
    void expiredToken_LeavesTheRequestAnonymous() throws Exception {
        run("Bearer " + token("user-4", Map.of(), SECRET, -60_000));

        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
    }

    @Test
    void malformedToken_LeavesTheRequestAnonymous() throws Exception {
        run("Bearer not-a-jwt");

        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
    }

    @Test
    void missingAuthorizationHeader_LeavesTheRequestAnonymous() throws Exception {
        run(null);

        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
    }

    @Test
    void nonBearerHeader_IsIgnored() throws Exception {
        run("Basic dXNlcjpwYXNz");

        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
    }

    @Test
    void theRequestAlwaysContinuesDownTheChain() throws Exception {
        MockFilterChain chain = run("Bearer not-a-jwt");

        assertThat(chain.getRequest()).isNotNull();
    }
}
