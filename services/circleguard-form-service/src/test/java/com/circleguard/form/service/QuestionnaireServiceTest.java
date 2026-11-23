package com.circleguard.form.service;

import com.circleguard.form.model.Question;
import com.circleguard.form.model.Questionnaire;
import com.circleguard.form.repository.QuestionnaireRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class QuestionnaireServiceTest {

    @Mock
    private QuestionnaireRepository repository;

    @InjectMocks
    private QuestionnaireService service;

    private static Questionnaire questionnaire(boolean active) {
        return Questionnaire.builder().id(UUID.randomUUID()).title("q").version(1).isActive(active).build();
    }

    @Test
    void getAllQuestionnaires_ReturnsEverythingStored() {
        List<Questionnaire> all = List.of(questionnaire(true), questionnaire(false));
        when(repository.findAll()).thenReturn(all);

        assertThat(service.getAllQuestionnaires()).isSameAs(all);
    }

    @Test
    void getActiveQuestionnaire_ReturnsTheNewestActiveVersion() {
        Questionnaire active = questionnaire(true);
        when(repository.findFirstByIsActiveTrueOrderByVersionDesc()).thenReturn(Optional.of(active));

        assertThat(service.getActiveQuestionnaire()).contains(active);
    }

    @Test
    void getActiveQuestionnaire_WhenNoneIsActive_IsEmpty() {
        when(repository.findFirstByIsActiveTrueOrderByVersionDesc()).thenReturn(Optional.empty());

        assertThat(service.getActiveQuestionnaire()).isEmpty();
    }

    @Test
    void saveQuestionnaire_LinksEveryQuestionBackToItsQuestionnaire() {
        Question first = Question.builder().text("fever?").orderIndex(1).build();
        Question second = Question.builder().text("cough?").orderIndex(2).build();
        Questionnaire input = Questionnaire.builder().title("daily").questions(List.of(first, second)).build();
        when(repository.save(input)).thenReturn(input);

        Questionnaire saved = service.saveQuestionnaire(input);

        assertThat(saved).isSameAs(input);
        assertThat(first.getQuestionnaire()).isSameAs(input);
        assertThat(second.getQuestionnaire()).isSameAs(input);
    }

    @Test
    void saveQuestionnaire_WithoutQuestions_StillSaves() {
        Questionnaire input = Questionnaire.builder().title("empty").build();
        when(repository.save(input)).thenReturn(input);

        assertThat(service.saveQuestionnaire(input)).isSameAs(input);
    }

    @Test
    void activateQuestionnaire_DeactivatesTheOthersAndActivatesTheTarget() {
        Questionnaire currentlyActive = questionnaire(true);
        Questionnaire target = questionnaire(false);
        when(repository.findAll()).thenReturn(List.of(currentlyActive, target));
        when(repository.findById(target.getId())).thenReturn(Optional.of(target));

        service.activateQuestionnaire(target.getId());

        assertThat(currentlyActive.getIsActive()).isFalse();
        assertThat(target.getIsActive()).isTrue();
        verify(repository).save(currentlyActive);
        verify(repository).save(target);
    }

    @Test
    void activateQuestionnaire_UnknownId_OnlyDeactivatesTheCurrentOne() {
        Questionnaire currentlyActive = questionnaire(true);
        UUID unknown = UUID.randomUUID();
        when(repository.findAll()).thenReturn(List.of(currentlyActive));
        when(repository.findById(unknown)).thenReturn(Optional.empty());

        service.activateQuestionnaire(unknown);

        assertThat(currentlyActive.getIsActive()).isFalse();
        verify(repository).save(currentlyActive);
        verify(repository, org.mockito.Mockito.times(1)).save(any(Questionnaire.class));
    }
}
