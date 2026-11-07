package com.circleguard.form.model;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/** The JPA lifecycle callbacks are protected, so this test lives in the same package. */
class QuestionnaireLifecycleTest {

    @Test
    void onCreate_SetsTheTimestampsAndTheDefaults() {
        Questionnaire questionnaire = new Questionnaire();

        questionnaire.onCreate();

        assertThat(questionnaire.getCreatedAt()).isNotNull();
        assertThat(questionnaire.getUpdatedAt()).isNotNull();
        assertThat(questionnaire.getVersion()).isEqualTo(1);
        assertThat(questionnaire.getIsActive()).isFalse();
    }

    @Test
    void onCreate_KeepsTheVersionAndActiveFlagAlreadySet() {
        Questionnaire questionnaire = Questionnaire.builder().version(4).isActive(true).build();

        questionnaire.onCreate();

        assertThat(questionnaire.getVersion()).isEqualTo(4);
        assertThat(questionnaire.getIsActive()).isTrue();
    }

    @Test
    void onUpdate_RefreshesOnlyTheUpdateTimestamp() throws Exception {
        Questionnaire questionnaire = new Questionnaire();
        questionnaire.onCreate();
        var created = questionnaire.getCreatedAt();
        Thread.sleep(5);

        questionnaire.onUpdate();

        assertThat(questionnaire.getCreatedAt()).isEqualTo(created);
        assertThat(questionnaire.getUpdatedAt()).isAfter(created);
    }
}
