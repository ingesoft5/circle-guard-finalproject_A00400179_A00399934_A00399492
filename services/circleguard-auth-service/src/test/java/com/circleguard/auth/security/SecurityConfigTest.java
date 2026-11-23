package com.circleguard.auth.security;

import com.circleguard.auth.service.CustomUserDetailsService;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.security.authentication.dao.DaoAuthenticationProvider;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.ldap.authentication.LdapAuthenticationProvider;
import org.springframework.ldap.core.support.LdapContextSource;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

class SecurityConfigTest {

    private final SecurityConfig config = new SecurityConfig();

    @Test
    void passwordEncoder_IsBcryptAndNeverStoresPlainText() {
        PasswordEncoder encoder = config.passwordEncoder();

        String hash = encoder.encode("a-test-password");

        assertThat(hash).startsWith("$2").isNotEqualTo("a-test-password");
        assertThat(encoder.matches("a-test-password", hash)).isTrue();
        assertThat(encoder.matches("another", hash)).isFalse();
    }

    @Test
    void corsConfiguration_AllowsOnlyTheKnownOriginsAndMethods() {
        CorsConfigurationSource source = config.corsConfigurationSource();

        CorsConfiguration cors = source.getCorsConfiguration(new MockHttpServletRequest("GET", "/api/v1/anything"));

        assertThat(cors).isNotNull();
        assertThat(cors.getAllowedOrigins()).containsExactly("http://localhost:8081", "http://localhost:8080");
        assertThat(cors.getAllowedMethods()).contains("GET", "POST", "PUT", "DELETE", "OPTIONS");
        assertThat(cors.getAllowCredentials()).isTrue();
    }

    @Test
    void ldapContextSource_UsesTheExternalConfiguration() {
        LdapContextSource source = config.contextSource(new String[] {"ldap://openldap:389"}, "dc=circleguard,dc=edu",
                "cn=admin,dc=circleguard,dc=edu", "from-configuration");
        source.afterPropertiesSet();

        assertThat(source.getBaseLdapPathAsString()).isEqualTo("dc=circleguard,dc=edu");
        assertThat(source.getUrls()).containsExactly("ldap://openldap:389");
        assertThat(source.getUserDn()).isEqualTo("cn=admin,dc=circleguard,dc=edu");
    }

    @Test
    void ldapContextSource_DoesNotHardCodeTheBindPassword() {
        LdapContextSource first = config.contextSource(new String[] {"ldap://a:389"}, "dc=x", "cn=admin,dc=x", "pw-one");
        LdapContextSource second = config.contextSource(new String[] {"ldap://a:389"}, "dc=x", "cn=admin,dc=x", "pw-two");

        first.afterPropertiesSet();
        second.afterPropertiesSet();

        assertThat(first.getAuthenticationSource().getCredentials()).isEqualTo("pw-one");
        assertThat(second.getAuthenticationSource().getCredentials()).isEqualTo("pw-two");
    }

    @Test
    void ldapAuthenticationProvider_IsBuiltFromTheContextSource() {
        LdapContextSource source = config.contextSource(new String[] {"ldap://localhost:389"}, "dc=circleguard,dc=edu",
                "cn=admin,dc=circleguard,dc=edu", "unused");

        LdapAuthenticationProvider provider = config.ldapAuthenticationProvider(source);

        assertThat(provider).isNotNull();
    }

    @Test
    void daoAuthenticationProvider_UsesTheGivenEncoderAndUserService() {
        CustomUserDetailsService users = mock(CustomUserDetailsService.class);
        PasswordEncoder encoder = config.passwordEncoder();

        DaoAuthenticationProvider provider = config.daoAuthenticationProvider(users, encoder);

        assertThat(provider).isNotNull();
    }
}
