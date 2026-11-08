package com.circleguard.form.service;

import com.circleguard.form.model.HealthSurvey;
import com.circleguard.form.model.Questionnaire;
import com.circleguard.form.model.ValidationStatus;
import com.circleguard.form.repository.HealthSurveyRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.kafka.core.KafkaTemplate;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class HealthSurveyServiceTest {

    @Mock
    private HealthSurveyRepository repository;
    @Mock
    private QuestionnaireService questionnaireService;
    @Mock
    private SymptomMapper symptomMapper;
    @Mock
    private KafkaTemplate<String, Object> kafkaTemplate;

    @InjectMocks
    private HealthSurveyService service;

    private UUID anonymousId;

    @BeforeEach
    void setUp() {
        anonymousId = UUID.randomUUID();
    }

    private HealthSurvey survey() {
        return HealthSurvey.builder().id(UUID.randomUUID()).anonymousId(anonymousId).build();
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> publishedEvent(String topic) {
        ArgumentCaptor<Object> event = ArgumentCaptor.forClass(Object.class);
        verify(kafkaTemplate).send(eq(topic), eq(anonymousId.toString()), event.capture());
        return (Map<String, Object>) event.getValue();
    }

    @Test
    void submitSurvey_WithSymptoms_PublishesSurveySubmittedWithHasSymptomsTrue() {
        Questionnaire active = Questionnaire.builder().title("daily").build();
        HealthSurvey input = survey();
        when(questionnaireService.getActiveQuestionnaire()).thenReturn(Optional.of(active));
        when(symptomMapper.hasSymptoms(input, active)).thenReturn(true);
        when(repository.save(input)).thenReturn(input);

        HealthSurvey saved = service.submitSurvey(input);

        assertThat(saved).isSameAs(input);
        Map<String, Object> event = publishedEvent("survey.submitted");
        assertThat(event).containsEntry("anonymousId", anonymousId).containsEntry("hasSymptoms", true);
        assertThat(event).containsKey("timestamp");
    }

    @Test
    void submitSurvey_WithoutSymptoms_PublishesHasSymptomsFalse() {
        Questionnaire active = Questionnaire.builder().title("daily").build();
        HealthSurvey input = survey();
        when(questionnaireService.getActiveQuestionnaire()).thenReturn(Optional.of(active));
        when(symptomMapper.hasSymptoms(input, active)).thenReturn(false);
        when(repository.save(input)).thenReturn(input);

        service.submitSurvey(input);

        assertThat(publishedEvent("survey.submitted")).containsEntry("hasSymptoms", false);
    }

    @Test
    void submitSurvey_WithoutAnActiveQuestionnaire_AssumesNoSymptoms() {
        HealthSurvey input = survey();
        when(questionnaireService.getActiveQuestionnaire()).thenReturn(Optional.empty());
        when(repository.save(input)).thenReturn(input);

        service.submitSurvey(input);

        assertThat(publishedEvent("survey.submitted")).containsEntry("hasSymptoms", false);
    }

    @Test
    void submitSurvey_FillsTheLegacyFieldsWhenTheyAreMissing() {
        Questionnaire active = Questionnaire.builder().title("daily").build();
        HealthSurvey input = survey();
        when(questionnaireService.getActiveQuestionnaire()).thenReturn(Optional.of(active));
        when(symptomMapper.hasSymptoms(input, active)).thenReturn(true);
        when(repository.save(input)).thenReturn(input);

        service.submitSurvey(input);

        assertThat(input.getHasFever()).isTrue();
        assertThat(input.getHasCough()).isTrue();
    }

    @Test
    void submitSurvey_KeepsTheLegacyFieldsTheClientSent() {
        HealthSurvey input = survey();
        input.setHasFever(false);
        input.setHasCough(false);
        when(questionnaireService.getActiveQuestionnaire()).thenReturn(Optional.empty());
        when(repository.save(input)).thenReturn(input);

        service.submitSurvey(input);

        assertThat(input.getHasFever()).isFalse();
        assertThat(input.getHasCough()).isFalse();
    }

    @Test
    void submitSurvey_WithAnAttachment_StartsAsPending() {
        HealthSurvey input = survey();
        input.setAttachmentPath("certificate.pdf");
        when(questionnaireService.getActiveQuestionnaire()).thenReturn(Optional.empty());
        when(repository.save(input)).thenReturn(input);

        service.submitSurvey(input);

        assertThat(input.getValidationStatus()).isEqualTo(ValidationStatus.PENDING);
    }

    @Test
    void submitSurvey_WithoutAnAttachment_HasNoValidationStatus() {
        HealthSurvey input = survey();
        when(questionnaireService.getActiveQuestionnaire()).thenReturn(Optional.empty());
        when(repository.save(input)).thenReturn(input);

        service.submitSurvey(input);

        assertThat(input.getValidationStatus()).isNull();
    }

    @Test
    void getPendingSurveys_ReturnsThoseWaitingForValidation() {
        List<HealthSurvey> pending = List.of(survey());
        when(repository.findByAttachmentPathIsNotNullAndValidationStatus(ValidationStatus.PENDING)).thenReturn(pending);

        assertThat(service.getPendingSurveys()).isSameAs(pending);
    }

    @Test
    void validateSurvey_Approved_PublishesCertificateValidated() {
        HealthSurvey stored = survey();
        UUID adminId = UUID.randomUUID();
        when(repository.findById(stored.getId())).thenReturn(Optional.of(stored));

        service.validateSurvey(stored.getId(), ValidationStatus.APPROVED, adminId);

        assertThat(stored.getValidationStatus()).isEqualTo(ValidationStatus.APPROVED);
        assertThat(stored.getValidatedBy()).isEqualTo(adminId);
        verify(repository).save(stored);
        Map<String, Object> event = publishedEvent("certificate.validated");
        assertThat(event).containsEntry("status", "APPROVED").containsEntry("adminId", adminId)
                .containsEntry("anonymousId", anonymousId);
    }

    @Test
    void validateSurvey_Rejected_SavesButPublishesNothing() {
        HealthSurvey stored = survey();
        when(repository.findById(stored.getId())).thenReturn(Optional.of(stored));

        service.validateSurvey(stored.getId(), ValidationStatus.REJECTED, UUID.randomUUID());

        assertThat(stored.getValidationStatus()).isEqualTo(ValidationStatus.REJECTED);
        verify(repository).save(stored);
        verify(kafkaTemplate, never()).send(anyString(), anyString(), any());
    }

    @Test
    void validateSurvey_UnknownSurvey_Throws() {
        UUID unknown = UUID.randomUUID();
        when(repository.findById(unknown)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.validateSurvey(unknown, ValidationStatus.APPROVED, UUID.randomUUID()))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining(unknown.toString());
        verify(kafkaTemplate, never()).send(anyString(), anyString(), any());
    }
}
