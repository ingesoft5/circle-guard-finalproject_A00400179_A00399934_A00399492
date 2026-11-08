// Integration tests (HU-04): Testcontainers against the Docker-in-Docker daemon of the controller.
//  - per-service *IntegrationTest classes (promotion: Neo4j + Redis + Postgres);
//  - the cross-service module tests/integration (form -> Kafka -> promotion -> Kafka -> notification).
def call(List<String> services) {
    if (!services) {
        return
    }
    boolean crossService = services.any { it in ['circleguard-form-service', 'circleguard-promotion-service', 'circleguard-notification-service'] }
    try {
        cgGradle('integrationTest', services, crossService ? ':tests:integration:integrationTest' : '')
    } finally {
        junit allowEmptyResults: true, testResults: 'services/*/build/test-results/integrationTest/*.xml,tests/integration/build/test-results/integrationTest/*.xml'
        archiveArtifacts artifacts: 'tests/integration/build/reports/tests/integrationTest/**,services/*/build/reports/tests/integrationTest/**', allowEmptyArchive: true
        publishIntegrationReport(crossService)
    }
}

def publishIntegrationReport(boolean crossService) {
    if (!crossService) {
        return
    }
    publishHTML(target: [
        reportName: 'Integration tests (cross-service)',
        reportDir: 'tests/integration/build/reports/tests/integrationTest',
        reportFiles: 'index.html',
        keepAll: true,
        alwaysLinkToLastBuild: true,
        allowMissing: true
    ])
}
