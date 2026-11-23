package com.circleguard.form.controller;

import com.circleguard.form.model.Questionnaire;
import com.circleguard.form.service.QuestionnaireService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** The endpoints of the questionnaire controller that the original test does not exercise. */
@WebMvcTest(QuestionnaireController.class)
class QuestionnaireControllerFlowsTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private QuestionnaireService service;

    @Test
    void getAll_ListsEveryQuestionnaire() throws Exception {
        when(service.getAllQuestionnaires()).thenReturn(List.of(
                Questionnaire.builder().title("one").version(1).build(),
                Questionnaire.builder().title("two").version(2).build()));

        mockMvc.perform(get("/api/v1/questionnaires"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(2))
                .andExpect(jsonPath("$[1].title").value("two"));
    }

    @Test
    void getActive_WhenNoneIsActive_Returns404() throws Exception {
        when(service.getActiveQuestionnaire()).thenReturn(Optional.empty());

        mockMvc.perform(get("/api/v1/questionnaires/active")).andExpect(status().isNotFound());
    }

    @Test
    void activate_DelegatesToTheService() throws Exception {
        UUID id = UUID.randomUUID();

        mockMvc.perform(post("/api/v1/questionnaires/{id}/activate", id)).andExpect(status().isOk());

        verify(service).activateQuestionnaire(id);
    }
}
