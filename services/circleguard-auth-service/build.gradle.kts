plugins {
    id("org.springframework.boot")
    id("io.spring.dependency-management")
    kotlin("jvm")
    kotlin("plugin.spring")
    kotlin("plugin.jpa")
}

dependencies {
    implementation(platform("org.springframework.boot:spring-boot-dependencies:3.2.4"))
    testImplementation(platform("org.springframework.boot:spring-boot-dependencies:3.2.4"))

    implementation("org.springframework.boot:spring-boot-starter-web")
    // HU-13: metrics, tracing and health probes for Prometheus/Grafana/Jaeger.
    implementation("org.springframework.boot:spring-boot-starter-actuator")
    implementation("io.micrometer:micrometer-registry-prometheus")
    implementation("io.micrometer:micrometer-tracing-bridge-otel")
    implementation("io.opentelemetry:opentelemetry-exporter-otlp")
    implementation("org.springframework.boot:spring-boot-starter-data-jpa")
    implementation("org.springframework.boot:spring-boot-starter-security")
    implementation("org.springframework.boot:spring-boot-starter-data-ldap")
    implementation("org.springframework.security:spring-security-ldap")
    implementation("io.jsonwebtoken:jjwt-api:0.11.5")
    runtimeOnly("io.jsonwebtoken:jjwt-impl:0.11.5")
    runtimeOnly("io.jsonwebtoken:jjwt-jackson:0.11.5")
    implementation("org.flywaydb:flyway-core")
    runtimeOnly("org.postgresql:postgresql")
    // HU-12: Circuit Breaker around the call to identity-service. Core module only (no AOP, no Actuator).
    implementation("io.github.resilience4j:resilience4j-circuitbreaker:2.2.0")
    // HU-13: expose the circuit breaker state and metrics to Micrometer.
    implementation("io.github.resilience4j:resilience4j-micrometer:2.2.0")
    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testImplementation("org.springframework.security:spring-security-test")
}
