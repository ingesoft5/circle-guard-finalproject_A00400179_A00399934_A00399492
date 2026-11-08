// Unit tests of the selected services, with the JaCoCo coverage gate (HU-04).
// `gradle test` already fails below 60 % of covered lines for the core services (JaCoCo verification);
// here the reports are published: JUnit, Coverage plugin, HTML per service and the summary table.
def call(List<String> services) {
    if (!services) {
        return
    }
    try {
        cgGradle('test jacocoTestReport', services)
    } finally {
        junit allowEmptyResults: true, testResults: 'services/*/build/test-results/test/*.xml'
        publishCoverage(services)
    }
}

def publishCoverage(List<String> services) {
    List<String> core = services.findAll { it in coreServices() }
    archiveArtifacts artifacts: 'services/*/build/reports/jacoco/test/*.xml,services/*/build/reports/jacoco/test/html/**', allowEmptyArchive: true
    if (!core) {
        return
    }
    sh './gradlew coverageSummary --no-daemon --console=plain || true'
    archiveArtifacts artifacts: 'build/reports/coverage-summary.md', allowEmptyArchive: true
    recordCoverage(
        id: 'jacoco',
        name: 'JaCoCo',
        tools: [[parser: 'JACOCO', pattern: core.collect { "services/${it}/build/reports/jacoco/test/jacocoTestReport.xml" }.join(',')]],
        qualityGates: [[threshold: 60.0, metric: 'LINE', baseline: 'PROJECT', criticality: 'FAILURE']]
    )
    core.each { service ->
        publishHTML(target: [
            reportName: "JaCoCo ${service}",
            reportDir: "services/${service}/build/reports/jacoco/test/html",
            reportFiles: 'index.html',
            keepAll: true,
            alwaysLinkToLastBuild: true,
            allowMissing: true
        ])
    }
}

// Services whose line coverage must stay at or above 60 % (same list as build.gradle.kts).
def coreServices() {
    return ['circleguard-auth-service', 'circleguard-identity-service', 'circleguard-promotion-service',
            'circleguard-form-service', 'circleguard-gateway-service']
}
