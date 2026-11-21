package com.circleguard.auth.service;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.config.YamlPropertiesFactoryBean;
import org.springframework.core.io.FileSystemResource;

import java.nio.file.Path;
import java.util.Properties;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * HU-15 finding: application.yml said qr.expiration: 300, but QrTokenService reads the value as MILLISECONDS, so a QR lived 300 ms and
 * the gate rejected tokens as soon as validation took longer than that. This pins the production configuration to a sane lifetime.
 */
class QrExpirationConfigurationTest {

    private static Properties mainConfiguration() {
        YamlPropertiesFactoryBean yaml = new YamlPropertiesFactoryBean();
        // build/resources/main/application.yml is the production file (src/test/resources has its own application.yml).
        yaml.setResources(new FileSystemResource(Path.of("src", "main", "resources", "application.yml")));
        return yaml.getObject();
    }

    @Test
    void qrExpiration_IsSixtySeconds_InMilliseconds() {
        long expiration = Long.parseLong(mainConfiguration().getProperty("qr.expiration"));

        assertThat(expiration).isEqualTo(60_000L);
    }

    @Test
    void qrExpiration_IsNeverShorterThanTheGateNeedsToValidate() {
        long expiration = Long.parseLong(mainConfiguration().getProperty("qr.expiration"));

        assertThat(expiration).as("a QR must live at least 10 s (it is in milliseconds)").isGreaterThanOrEqualTo(10_000L);
    }
}
