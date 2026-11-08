package com.circleguard.form.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.UUID;

@Service
public class StorageService {

    private final Path root;

    // The folder is configurable so the service can be tested with a temporary directory; the default keeps the
    // location used until now.
    public StorageService(@Value("${circleguard.storage.root:/tmp/circleguard-uploads}") String rootDirectory) {
        this.root = Paths.get(rootDirectory);
        try {
            Files.createDirectories(root);
        } catch (IOException e) {
            throw new RuntimeException("Could not initialize storage", e);
        }
    }

    public String store(MultipartFile file) {
        try {
            String filename = UUID.randomUUID() + "_" + file.getOriginalFilename();
            Files.copy(file.getInputStream(), this.root.resolve(filename));
            return filename;
        } catch (Exception e) {
            throw new RuntimeException("Could not store the file. Error: " + e.getMessage());
        }
    }
}
