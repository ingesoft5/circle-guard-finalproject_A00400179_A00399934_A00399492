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
    archiveArtifacts artifacts: 'services/*/build/reports/jacoco/test/*.xml,services/*/build/reports/jacoco/test/html/**', allowEmptyArchive: true
}
