package com.circleguard.file.service;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashSet;
import java.util.Set;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * HU-15 (quality finding): the file service had three tests and 46.7 % line coverage. FileStorageService writes into a relative
 * "uploads" directory of the working directory, so these tests record what existed before and remove everything they create.
 */
class FileStorageServiceTest {

    private static final Path UPLOADS = Path.of("uploads");

    private boolean uploadsExistedBefore;
    private Set<Path> filesBefore;

    private static Set<Path> list() throws IOException {
        if (!Files.exists(UPLOADS)) {
            return new HashSet<>();
        }
        try (Stream<Path> stream = Files.list(UPLOADS)) {
            return new HashSet<>(stream.toList());
        }
    }

    @BeforeEach
    void remember() throws IOException {
        uploadsExistedBefore = Files.exists(UPLOADS);
        filesBefore = list();
    }

    @AfterEach
    void cleanUp() throws IOException {
        for (Path created : list()) {
            if (!filesBefore.contains(created)) {
                Files.deleteIfExists(created);
            }
        }
        if (!uploadsExistedBefore) {
            Files.deleteIfExists(UPLOADS);
        }
    }

    @Test
    void constructor_CreatesTheUploadsDirectory() {
        new FileStorageService();

        assertThat(Files.isDirectory(UPLOADS)).isTrue();
    }

    @Test
    void saveFile_StoresTheContentUnderAGeneratedName() throws IOException {
        FileStorageService service = new FileStorageService();
        MultipartFile file = new MockMultipartFile("file", "certificate.pdf", "application/pdf", "mock content".getBytes());

        String stored = service.saveFile(file);

        assertThat(stored).endsWith("_certificate.pdf").hasSizeGreaterThan("certificate.pdf".length());
        assertThat(Files.readString(UPLOADS.resolve(stored))).isEqualTo("mock content");
    }

    @Test
    void saveFile_TwoUploadsWithTheSameNameDoNotOverwriteEachOther() {
        FileStorageService service = new FileStorageService();
        MultipartFile first = new MockMultipartFile("file", "same.txt", "text/plain", "one".getBytes());
        MultipartFile second = new MockMultipartFile("file", "same.txt", "text/plain", "two".getBytes());

        assertThat(service.saveFile(first)).isNotEqualTo(service.saveFile(second));
    }

    @Test
    void saveFile_ANameWithPathTraversalDoesNotWriteOutsideTheUploadsDirectory() {
        FileStorageService service = new FileStorageService();
        MultipartFile malicious = new MockMultipartFile("file", "../evil.txt", "text/plain", "x".getBytes());

        assertThatThrownBy(() -> service.saveFile(malicious)).isInstanceOf(RuntimeException.class).hasMessage("Could not store file");
        assertThat(Files.exists(Path.of("evil.txt"))).isFalse();
    }

    @Test
    void saveFile_WhenReadingTheUploadFails_ReportsAStorageError() throws IOException {
        FileStorageService service = new FileStorageService();
        MultipartFile broken = mock(MultipartFile.class);
        when(broken.getOriginalFilename()).thenReturn("broken.bin");
        when(broken.getInputStream()).thenThrow(new IOException("disk error"));

        assertThatThrownBy(() -> service.saveFile(broken)).isInstanceOf(RuntimeException.class).hasMessage("Could not store file");
    }

    @Test
    void saveFile_AnEmptyStreamStillStoresAnEmptyFile() throws IOException {
        FileStorageService service = new FileStorageService();
        MultipartFile empty = mock(MultipartFile.class);
        when(empty.getOriginalFilename()).thenReturn("empty.txt");
        when(empty.getInputStream()).thenReturn(InputStream.nullInputStream());

        String stored = service.saveFile(empty);

        assertThat(Files.size(UPLOADS.resolve(stored))).isZero();
    }

    @Test
    void loadFile_IsNotImplementedYet_AndReturnsNull() {
        assertThat(new FileStorageService().loadFile("anything")).isNull();
    }
}
