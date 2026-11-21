package com.circleguard.file.controller;

import com.circleguard.file.service.FileStorageService;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.multipart.MultipartFile;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** HU-15 (quality finding): error paths of the upload endpoint. */
@WebMvcTest(FileUploadController.class)
class FileUploadControllerEdgeCasesTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private FileStorageService storageService;

    @Test
    void upload_WithoutTheFilePart_IsABadRequestAndStoresNothing() throws Exception {
        mockMvc.perform(multipart("/api/v1/files/upload")).andExpect(status().isBadRequest());

        Mockito.verifyNoInteractions(storageService);
    }

    @Test
    void upload_HandsTheOriginalFileToTheStorageService() throws Exception {
        MockMultipartFile file = new MockMultipartFile("file", "certificate.pdf", "application/pdf", "content".getBytes());
        Mockito.when(storageService.saveFile(Mockito.any())).thenReturn("id_certificate.pdf");
        ArgumentCaptor<MultipartFile> captured = ArgumentCaptor.forClass(MultipartFile.class);

        mockMvc.perform(multipart("/api/v1/files/upload").file(file)).andExpect(status().isOk());

        Mockito.verify(storageService).saveFile(captured.capture());
        assertThat(captured.getValue().getOriginalFilename()).isEqualTo("certificate.pdf");
        assertThat(captured.getValue().getBytes()).isEqualTo("content".getBytes());
    }

    @Test
    void upload_WhenStorageFails_TheErrorIsNotSwallowed() {
        MockMultipartFile file = new MockMultipartFile("file", "certificate.pdf", "application/pdf", "content".getBytes());
        Mockito.when(storageService.saveFile(Mockito.any())).thenThrow(new RuntimeException("Could not store file"));

        assertThatThrownBy(() -> mockMvc.perform(multipart("/api/v1/files/upload").file(file))).hasRootCauseMessage("Could not store file");
    }

    @Test
    void upload_OnlyAcceptsPost() throws Exception {
        mockMvc.perform(get("/api/v1/files/upload")).andExpect(status().isMethodNotAllowed());
    }
}
