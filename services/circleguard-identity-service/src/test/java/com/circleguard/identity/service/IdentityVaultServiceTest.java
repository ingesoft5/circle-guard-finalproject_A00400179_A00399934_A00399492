package com.circleguard.identity.service;

import com.circleguard.identity.model.IdentityMapping;
import com.circleguard.identity.repository.IdentityMappingRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.server.ResponseStatusException;

import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class IdentityVaultServiceTest {

    @Mock
    private IdentityMappingRepository repository;

    @InjectMocks
    private IdentityVaultService service;

    @BeforeEach
    void setUp() {
        ReflectionTestUtils.setField(service, "hashSalt", "unit-test-salt");
    }

    @Test
    void getOrCreateAnonymousId_ReturnsTheExistingMappingWithoutSaving() {
        UUID existing = UUID.randomUUID();
        when(repository.findByIdentityHash(anyString()))
                .thenReturn(Optional.of(IdentityMapping.builder().anonymousId(existing).build()));

        assertThat(service.getOrCreateAnonymousId("alice@example.com")).isEqualTo(existing);
        verify(repository, never()).save(any());
    }

    @Test
    void getOrCreateAnonymousId_CreatesAMappingForANewIdentity() {
        UUID created = UUID.randomUUID();
        when(repository.findByIdentityHash(anyString())).thenReturn(Optional.empty());
        when(repository.save(any(IdentityMapping.class)))
                .thenReturn(IdentityMapping.builder().anonymousId(created).build());

        UUID result = service.getOrCreateAnonymousId("bob@example.com");

        assertThat(result).isEqualTo(created);
        ArgumentCaptor<IdentityMapping> saved = ArgumentCaptor.forClass(IdentityMapping.class);
        verify(repository).save(saved.capture());
        assertThat(saved.getValue().getRealIdentity()).isEqualTo("bob@example.com");
        assertThat(saved.getValue().getSalt()).isNotBlank();
    }

    @Test
    void getOrCreateAnonymousId_StoresASha256HashAndNeverTheClearIdentity() {
        when(repository.findByIdentityHash(anyString())).thenReturn(Optional.empty());
        when(repository.save(any(IdentityMapping.class))).thenReturn(IdentityMapping.builder().build());

        service.getOrCreateAnonymousId("carol@example.com");

        ArgumentCaptor<IdentityMapping> saved = ArgumentCaptor.forClass(IdentityMapping.class);
        verify(repository).save(saved.capture());
        assertThat(saved.getValue().getIdentityHash()).hasSize(64).matches("[0-9a-f]+").doesNotContain("carol");
    }

    @Test
    void getOrCreateAnonymousId_UsesTheSameHashForTheSameIdentity() {
        when(repository.findByIdentityHash(anyString())).thenReturn(Optional.empty());
        when(repository.save(any(IdentityMapping.class))).thenReturn(IdentityMapping.builder().build());

        service.getOrCreateAnonymousId("dave@example.com");
        service.getOrCreateAnonymousId("dave@example.com");
        service.getOrCreateAnonymousId("erin@example.com");

        ArgumentCaptor<String> hashes = ArgumentCaptor.forClass(String.class);
        verify(repository, org.mockito.Mockito.times(3)).findByIdentityHash(hashes.capture());
        assertThat(hashes.getAllValues().get(0)).isEqualTo(hashes.getAllValues().get(1));
        assertThat(hashes.getAllValues().get(0)).isNotEqualTo(hashes.getAllValues().get(2));
    }

    @Test
    void resolveRealIdentity_ReturnsTheStoredIdentity() {
        UUID id = UUID.randomUUID();
        when(repository.findById(id)).thenReturn(Optional.of(IdentityMapping.builder().realIdentity("frank@example.com").build()));

        assertThat(service.resolveRealIdentity(id)).isEqualTo("frank@example.com");
    }

    @Test
    void resolveRealIdentity_UnknownId_Throws404() {
        UUID id = UUID.randomUUID();
        when(repository.findById(id)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.resolveRealIdentity(id))
                .isInstanceOfSatisfying(ResponseStatusException.class,
                        e -> assertThat(e.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND));
    }
}
