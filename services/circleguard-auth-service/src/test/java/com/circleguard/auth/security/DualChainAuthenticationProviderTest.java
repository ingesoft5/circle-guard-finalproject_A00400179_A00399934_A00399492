package com.circleguard.auth.security;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.DisabledException;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.authentication.dao.DaoAuthenticationProvider;
import org.springframework.security.core.Authentication;
import org.springframework.security.ldap.authentication.LdapAuthenticationProvider;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class DualChainAuthenticationProviderTest {

    @Mock
    private LdapAuthenticationProvider ldapProvider;

    @Mock
    private DaoAuthenticationProvider localProvider;

    @InjectMocks
    private DualChainAuthenticationProvider provider;

    private final Authentication request = new UsernamePasswordAuthenticationToken("alice", "secret");

    @Test
    void authenticate_UsesLdapFirstAndSkipsTheLocalDatabaseOnSuccess() {
        Authentication ldapResult = new TestingAuthenticationToken("alice", null, "ROLE_LDAP");
        when(ldapProvider.authenticate(request)).thenReturn(ldapResult);

        assertThat(provider.authenticate(request)).isSameAs(ldapResult);
        verify(localProvider, never()).authenticate(request);
    }

    @Test
    void authenticate_FallsBackToTheLocalDatabaseWhenLdapRejects() {
        Authentication localResult = new TestingAuthenticationToken("alice", null, "ROLE_LOCAL");
        when(ldapProvider.authenticate(request)).thenThrow(new BadCredentialsException("not in ldap"));
        when(localProvider.authenticate(request)).thenReturn(localResult);

        assertThat(provider.authenticate(request)).isSameAs(localResult);
    }

    @Test
    void authenticate_WhenBothChainsReject_ThrowsTheLocalError() {
        when(ldapProvider.authenticate(request)).thenThrow(new BadCredentialsException("not in ldap"));
        when(localProvider.authenticate(request)).thenThrow(new DisabledException("account disabled"));

        assertThatThrownBy(() -> provider.authenticate(request))
                .isInstanceOf(DisabledException.class)
                .hasMessage("account disabled");
    }

    @Test
    void supports_AcceptsUsernamePasswordTokensOnly() {
        assertThat(provider.supports(UsernamePasswordAuthenticationToken.class)).isTrue();
        assertThat(provider.supports(TestingAuthenticationToken.class)).isFalse();
    }
}
