package com.circleguard.identity.config;

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

    private static final String SECRET = "i".repeat(48);

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
    void validToken_AuthenticatesWithItsPermissions() throws Exception {
        run("Bearer " + token("anon-1", Map.of("permissions", List.of("identity:lookup")), SECRET, 60_000));

        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        assertThat(auth).isNotNull();
        assertThat(auth.getName()).isEqualTo("anon-1");
        assertThat(auth.getAuthorities().stream().map(GrantedAuthority::getAuthority))
                .containsExactly("identity:lookup");
    }

    @Test
    void tokenWithoutPermissions_DoesNotAuthenticate() throws Exception {
        run("Bearer " + token("anon-2", Map.of(), SECRET, 60_000));

        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
    }

    @Test
    void tokenSignedWithAnotherKey_DoesNotAuthenticate() throws Exception {
        run("Bearer " + token("anon-3", Map.of("permissions", List.of("x")), "j".repeat(48), 60_000));

        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
    }

    @Test
    void expiredToken_DoesNotAuthenticate() throws Exception {
        run("Bearer " + token("anon-4", Map.of("permissions", List.of("x")), SECRET, -60_000));

        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
    }

    @Test
    void malformedToken_DoesNotAuthenticate() throws Exception {
        run("Bearer garbage");

        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
    }

    @Test
    void requestsWithoutABearerHeader_PassThroughAnonymous() throws Exception {
        MockFilterChain noHeader = run(null);
        MockFilterChain basic = run("Basic dXNlcjpwYXNz");

        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
        assertThat(noHeader.getRequest()).isNotNull();
        assertThat(basic.getRequest()).isNotNull();
    }
}
