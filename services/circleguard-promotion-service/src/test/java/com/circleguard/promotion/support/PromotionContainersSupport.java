package com.circleguard.promotion.support;

import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.Neo4jContainer;
import org.testcontainers.containers.PostgreSQLContainer;

/**
 * Real Postgres, Neo4j and Redis shared by every promotion integration test (one start per JVM).
 * The containers are stopped by Testcontainers' Ryuk when the JVM ends.
 */
public abstract class PromotionContainersSupport {

    static final String NEO4J_PASSWORD = "it-" + Long.toHexString(System.nanoTime());

    protected static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:15-alpine");
    protected static final Neo4jContainer<?> NEO4J = new Neo4jContainer<>("neo4j:5.12.0").withAdminPassword(NEO4J_PASSWORD);
    protected static final GenericContainer<?> REDIS = new GenericContainer<>("redis:7.2.1").withExposedPorts(6379);

    static {
        POSTGRES.start();
        NEO4J.start();
        REDIS.start();
    }

    @DynamicPropertySource
    static void containerProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
        registry.add("spring.neo4j.uri", NEO4J::getBoltUrl);
        registry.add("spring.neo4j.authentication.username", () -> "neo4j");
        registry.add("spring.neo4j.authentication.password", () -> NEO4J_PASSWORD);
        registry.add("spring.data.redis.host", REDIS::getHost);
        registry.add("spring.data.redis.port", REDIS::getFirstMappedPort);
        // The listeners are exercised by the cross-service tests; here Kafka is mocked.
        registry.add("spring.kafka.listener.auto-startup", () -> "false");
    }
}
