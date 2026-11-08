package com.circleguard.auth.service;

import com.circleguard.auth.model.LocalUser;
import com.circleguard.auth.model.Permission;
import com.circleguard.auth.model.Role;
import com.circleguard.auth.repository.LocalUserRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.DisabledException;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UsernameNotFoundException;

import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class CustomUserDetailsServiceTest {

    @Mock
    private LocalUserRepository userRepository;

    @InjectMocks
    private CustomUserDetailsService service;

    private static LocalUser user(boolean active, Set<Role> roles) {
        return LocalUser.builder()
                .username("alice")
                .password("hash")
                .email("alice@example.com")
                .isActive(active)
                .roles(roles)
                .build();
    }

    private static Role role(String name, String... permissions) {
        Set<Permission> perms = java.util.Arrays.stream(permissions)
                .map(p -> Permission.builder().name(p).build())
                .collect(Collectors.toSet());
        return Role.builder().name(name).permissions(perms).build();
    }

    @Test
    void loadUserByUsername_ReturnsTheStoredCredentials() {
        when(userRepository.findByUsername("alice")).thenReturn(Optional.of(user(true, Set.of(role("STAFF")))));

        UserDetails details = service.loadUserByUsername("alice");

        assertThat(details.getUsername()).isEqualTo("alice");
        assertThat(details.getPassword()).isEqualTo("hash");
    }

    @Test
    void loadUserByUsername_PrefixesRolesAndAddsEveryPermission() {
        when(userRepository.findByUsername("alice"))
                .thenReturn(Optional.of(user(true, Set.of(role("ADMIN", "alert:send", "health:read")))));

        UserDetails details = service.loadUserByUsername("alice");

        assertThat(details.getAuthorities().stream().map(GrantedAuthority::getAuthority))
                .containsExactlyInAnyOrder("ROLE_ADMIN", "alert:send", "health:read");
    }

    @Test
    void loadUserByUsername_MergesTheAuthoritiesOfSeveralRoles() {
        when(userRepository.findByUsername("alice"))
                .thenReturn(Optional.of(user(true, Set.of(role("A", "p1"), role("B", "p2")))));

        UserDetails details = service.loadUserByUsername("alice");

        assertThat(details.getAuthorities()).hasSize(4);
    }

    @Test
    void loadUserByUsername_UnknownUser_Throws() {
        when(userRepository.findByUsername("ghost")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.loadUserByUsername("ghost"))
                .isInstanceOf(UsernameNotFoundException.class)
                .hasMessageContaining("ghost");
    }

    @Test
    void loadUserByUsername_DisabledUser_Throws() {
        when(userRepository.findByUsername("alice")).thenReturn(Optional.of(user(false, Set.of())));

        assertThatThrownBy(() -> service.loadUserByUsername("alice")).isInstanceOf(DisabledException.class);
    }
}
