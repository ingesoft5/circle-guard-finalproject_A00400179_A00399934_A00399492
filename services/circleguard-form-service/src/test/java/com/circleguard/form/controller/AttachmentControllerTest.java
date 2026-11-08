package com.circleguard.form.controller;

import com.circleguard.form.service.StorageService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.web.servlet.MockMvc;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * The controller is tested on its own: the storage is replaced by a mock, so the test needs neither a database
 * nor Kafka (the previous version loaded the whole application and failed with "Connection refused").
 */
@WebMvcTest(AttachmentController.class)
class AttachmentControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private StorageService storageService;

    @Test
    void shouldUploadFile() throws Exception {
        MockMultipartFile file = new MockMultipartFile(
                "file",
                "test.pdf",
                "application/pdf",
                "test data".getBytes()
        );
        when(storageService.store(any())).thenReturn("1234_test.pdf");

        mockMvc.perform(multipart("/api/v1/attachments").file(file))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.filename").value("1234_test.pdf"));

        verify(storageService).store(any());
    }

    @Test
    void shouldRejectARequestWithoutFile() throws Exception {
        mockMvc.perform(multipart("/api/v1/attachments"))
                .andExpect(status().isBadRequest());
    }
}
