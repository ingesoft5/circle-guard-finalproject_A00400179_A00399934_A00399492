package com.circleguard.form.service;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.mock.web.MockMultipartFile;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class StorageServiceTest {

    @TempDir
    Path tempDir;

    @Test
    void constructor_CreatesTheStorageFolderWhenItDoesNotExist() {
        Path folder = tempDir.resolve("uploads/nested");

        new StorageService(folder.toString());

        assertThat(folder).isDirectory();
    }

    @Test
    void store_WritesTheFileWithAUniquePrefixedName() throws Exception {
        StorageService service = new StorageService(tempDir.toString());
        MockMultipartFile file = new MockMultipartFile("file", "certificate.pdf", "application/pdf", "content".getBytes());

        String stored = service.store(file);

        assertThat(stored).endsWith("_certificate.pdf").hasSizeGreaterThan("_certificate.pdf".length());
        assertThat(Files.readString(tempDir.resolve(stored))).isEqualTo("content");
    }

    @Test
    void store_TheSameNameTwice_KeepsBothFiles() {
        StorageService service = new StorageService(tempDir.toString());
        MockMultipartFile file = new MockMultipartFile("file", "same.pdf", "application/pdf", "x".getBytes());

        String first = service.store(file);
        String second = service.store(file);

        assertThat(first).isNotEqualTo(second);
        assertThat(tempDir.resolve(first)).exists();
        assertThat(tempDir.resolve(second)).exists();
    }

    @Test
    void store_WhenTheFileCannotBeRead_ReportsTheError() {
        StorageService service = new StorageService(tempDir.toString());
        MockMultipartFile broken = new MockMultipartFile("file", "broken.pdf", "application/pdf", new byte[0]) {
            @Override
            public java.io.InputStream getInputStream() throws java.io.IOException {
                throw new java.io.IOException("disk error");
            }
        };

        assertThatThrownBy(() -> service.store(broken))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("Could not store the file")
                .hasMessageContaining("disk error");
    }

    @Test
    void constructor_WhenTheFolderCannotBeCreated_Fails() throws Exception {
        Path occupied = Files.createFile(tempDir.resolve("a-file"));

        assertThatThrownBy(() -> new StorageService(occupied.resolve("child").toString()))
                .isInstanceOf(RuntimeException.class)
                .hasMessage("Could not initialize storage");
    }
}
