package com.circleguard.it;

import com.circleguard.form.model.HealthSurvey;
import com.circleguard.form.model.Question;
import com.circleguard.form.model.QuestionType;
import com.circleguard.form.model.Questionnaire;
import com.circleguard.form.model.ValidationStatus;
import com.circleguard.form.repository.HealthSurveyRepository;
import com.circleguard.form.service.HealthSurveyService;
import com.circleguard.form.service.QuestionnaireService;
import com.circleguard.form.service.SymptomMapper;
import com.circleguard.notification.NotificationApplication;
import com.circleguard.promotion.PromotionApplication;
import org.apache.kafka.clients.admin.AdminClient;
import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.common.serialization.StringSerializer;
import org.springframework.boot.SpringApplication;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.kafka.config.KafkaListenerEndpointRegistry;
import org.springframework.kafka.core.DefaultKafkaProducerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.listener.MessageListenerContainer;
import org.springframework.kafka.support.serializer.JsonSerializer;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.KafkaContainer;
import org.testcontainers.containers.Neo4jContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.utility.DockerImageName;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * One environment for every cross-service integration test (started once per JVM):
 * Kafka, Postgres, Neo4j and Redis in containers, the promotion and notification applications booted with
 * their own application.yml, and the form service code that produces the events wired to the same Kafka.
 */
public final class IntegrationEnvironment {

    private static final String SERVICES = "../../services/";
    private static final String NEO4J_PASSWORD = "it-" + Long.toHexString(System.nanoTime());

    public static final KafkaContainer KAFKA = new KafkaContainer(DockerImageName.parse("confluentinc/cp-kafka:7.5.3"));
    public static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:15-alpine");
    public static final Neo4jContainer<?> NEO4J = new Neo4jContainer<>("neo4j:5.12.0").withAdminPassword(NEO4J_PASSWORD);
    public static final GenericContainer<?> REDIS = new GenericContainer<>("redis:7.2.1").withExposedPorts(6379);

    public static final List<String> TOPICS = List.of(
            "survey.submitted", "certificate.validated", "promotion.status.changed",
            "alert.priority", "circle.fenced", "notification.audit");

    private static ConfigurableApplicationContext promotion;
    private static ConfigurableApplicationContext notification;
    private static HealthSurveyRepository formRepository;
    private static QuestionnaireService formQuestionnaires;
    private static HealthSurveyService formSurveys;

    private IntegrationEnvironment() {
    }

    public static synchronized void start() throws Exception {
        if (promotion != null) {
            return;
        }
        KAFKA.start();
        POSTGRES.start();
        NEO4J.start();
        REDIS.start();
        createTopics();

        ConfigurableApplicationContext promotionContext = run(PromotionApplication.class, SERVICES + "circleguard-promotion-service/src/main/resources/application.yml",
                "--spring.datasource.url=" + POSTGRES.getJdbcUrl(),
                "--spring.datasource.username=" + POSTGRES.getUsername(),
                "--spring.datasource.password=" + POSTGRES.getPassword(),
                "--spring.jpa.hibernate.ddl-auto=create",
                "--spring.flyway.enabled=false",
                "--spring.neo4j.uri=" + NEO4J.getBoltUrl(),
                "--spring.neo4j.authentication.password=" + NEO4J_PASSWORD,
                "--spring.data.redis.host=" + REDIS.getHost(),
                "--spring.data.redis.port=" + REDIS.getFirstMappedPort());

        ConfigurableApplicationContext notificationContext = run(NotificationApplication.class, SERVICES + "circleguard-notification-service/src/main/resources/application.yml",
                // Promotion's persistence and security starters share the test classpath; notification uses none of them.
                "--spring.autoconfigure.exclude=" + String.join(",", List.of(
                        "org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration",
                        "org.springframework.boot.autoconfigure.orm.jpa.HibernateJpaAutoConfiguration",
                        "org.springframework.boot.autoconfigure.flyway.FlywayAutoConfiguration",
                        "org.springframework.boot.autoconfigure.data.jpa.JpaRepositoriesAutoConfiguration",
                        "org.springframework.boot.autoconfigure.neo4j.Neo4jAutoConfiguration",
                        "org.springframework.boot.autoconfigure.data.neo4j.Neo4jDataAutoConfiguration",
                        "org.springframework.boot.autoconfigure.data.neo4j.Neo4jRepositoriesAutoConfiguration",
                        "org.springframework.boot.autoconfigure.data.redis.RedisAutoConfiguration",
                        "org.springframework.boot.autoconfigure.data.redis.RedisRepositoriesAutoConfiguration",
                        "org.springframework.boot.autoconfigure.security.servlet.SecurityAutoConfiguration",
                        "org.springframework.boot.autoconfigure.security.servlet.UserDetailsServiceAutoConfiguration")));

        buildFormSide();
        waitForPartitions(promotionContext);
        waitForPartitions(notificationContext);
        notification = notificationContext;
        promotion = promotionContext;
    }

    private static ConfigurableApplicationContext run(Class<?> application, String configFile, String... overrides) {
        String[] common = {
                "--spring.config.location=file:" + configFile,
                "--spring.kafka.bootstrap-servers=" + KAFKA.getBootstrapServers(),
                "--server.port=0",
                "--spring.main.banner-mode=off"};
        String[] args = new String[common.length + overrides.length];
        System.arraycopy(common, 0, args, 0, common.length);
        System.arraycopy(overrides, 0, args, common.length, overrides.length);
        return SpringApplication.run(application, args);
    }

    /** The tests publish right away, so every @KafkaListener must already own its partitions. */
    private static void waitForPartitions(ConfigurableApplicationContext context) throws InterruptedException {
        var registry = context.getBean(KafkaListenerEndpointRegistry.class);
        long deadline = System.currentTimeMillis() + 120_000;
        for (MessageListenerContainer container : registry.getListenerContainers()) {
            while (container.getAssignedPartitions() == null || container.getAssignedPartitions().isEmpty()) {
                if (System.currentTimeMillis() > deadline) {
                    throw new IllegalStateException("Kafka listener without partitions: " + container.getListenerId());
                }
                Thread.sleep(250);
            }
        }
    }

    private static void createTopics() throws Exception {
        try (AdminClient admin = AdminClient.create(Map.<String, Object>of("bootstrap.servers", KAFKA.getBootstrapServers()))) {
            admin.createTopics(TOPICS.stream().map(t -> new NewTopic(t, 1, (short) 1)).toList()).all().get();
        }
    }

    /** The real HealthSurveyService and SymptomMapper of the form service, producing to the real Kafka. */
    private static void buildFormSide() {
        var factory = new DefaultKafkaProducerFactory<String, Object>(
                Map.<String, Object>of("bootstrap.servers", KAFKA.getBootstrapServers()),
                new StringSerializer(), new JsonSerializer<>());
        KafkaTemplate<String, Object> template = new KafkaTemplate<>(factory);

        formRepository = mock(HealthSurveyRepository.class);
        when(formRepository.save(any(HealthSurvey.class))).thenAnswer(i -> i.getArgument(0));
        formQuestionnaires = mock(QuestionnaireService.class);
        formSurveys = new HealthSurveyService(formRepository, formQuestionnaires, new SymptomMapper(), template);
    }

    public static ConfigurableApplicationContext promotion() {
        return promotion;
    }

    public static ConfigurableApplicationContext notification() {
        return notification;
    }

    public static String bootstrapServers() {
        return KAFKA.getBootstrapServers();
    }

    /** Submits a survey through the form service code; the answer to the fever question is YES or NO. */
    public static synchronized HealthSurvey submitSurvey(UUID anonymousId, boolean fever) {
        Question q = Question.builder().id(UUID.randomUUID()).text("Do you have fever?").type(QuestionType.YES_NO).orderIndex(1).build();
        Questionnaire questionnaire = Questionnaire.builder().id(UUID.randomUUID()).title("Daily").version(1).isActive(true)
                .questions(List.of(q)).build();
        when(formQuestionnaires.getActiveQuestionnaire()).thenReturn(Optional.of(questionnaire));
        HealthSurvey survey = HealthSurvey.builder().anonymousId(anonymousId)
                .responses(Map.of(q.getId().toString(), fever ? "YES" : "NO")).build();
        return formSurveys.submitSurvey(survey);
    }

    /** An admin approves the certificate of a survey; the form service emits certificate.validated. */
    public static synchronized void approveCertificate(UUID anonymousId) {
        UUID surveyId = UUID.randomUUID();
        HealthSurvey survey = HealthSurvey.builder().id(surveyId).anonymousId(anonymousId).build();
        when(formRepository.findById(surveyId)).thenReturn(Optional.of(survey));
        formSurveys.validateSurvey(surveyId, ValidationStatus.APPROVED, UUID.randomUUID());
    }

    /** Creates the user node, with one recent contact so the propagation query returns a row. */
    public static void createUser(String id, String status, Long statusUpdatedAt) {
        var neo4j = promotion.getBean(org.springframework.data.neo4j.core.Neo4jClient.class);
        neo4j.query("MERGE (u:User {anonymousId: $id}) SET u.status = $status, u.statusUpdatedAt = $at " +
                "MERGE (c:User {anonymousId: $contact}) ON CREATE SET c.status = 'ACTIVE' " +
                "MERGE (u)-[e:ENCOUNTERED]->(c) SET e.startTime = timestamp(), e.isValid = true")
                .bind(id).to("id").bind(status).to("status").bind(statusUpdatedAt).to("at")
                .bind("contact-of-" + id).to("contact").run();
    }

    /** Status stored in the graph for the user, or null. */
    public static String graphStatus(String id) {
        var neo4j = promotion.getBean(org.springframework.data.neo4j.core.Neo4jClient.class);
        return neo4j.query("MATCH (u:User {anonymousId: $id}) RETURN u.status AS s").bind(id).to("id")
                .fetchAs(String.class).one().orElse(null);
    }
}
