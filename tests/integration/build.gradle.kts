// HU-04: cross-service integration tests (Testcontainers). Real Kafka, Postgres, Neo4j and Redis;
// the real promotion and notification applications; the real form service code that produces the events.
dependencies {
    testAnnotationProcessor(platform("org.springframework.boot:spring-boot-dependencies:3.2.4"))
    testCompileOnly(platform("org.springframework.boot:spring-boot-dependencies:3.2.4"))
    testImplementation(platform("org.springframework.boot:spring-boot-dependencies:3.2.4"))
    testImplementation(project(":services:circleguard-form-service"))
    testImplementation(project(":services:circleguard-promotion-service"))
    testImplementation(project(":services:circleguard-notification-service"))

    testImplementation("org.springframework.boot:spring-boot-starter-web")
    testImplementation("org.springframework.boot:spring-boot-starter-data-jpa")
    testImplementation("org.springframework.boot:spring-boot-starter-data-neo4j")
    testImplementation("org.springframework.boot:spring-boot-starter-data-redis")
    testImplementation("org.springframework.kafka:spring-kafka")
    testImplementation("org.testcontainers:junit-jupiter:1.19.3")
    testImplementation("org.testcontainers:kafka:1.19.3")
    testImplementation("org.testcontainers:postgresql:1.19.3")
    testImplementation("org.testcontainers:neo4j:1.19.3")
    testImplementation("org.awaitility:awaitility")
}
