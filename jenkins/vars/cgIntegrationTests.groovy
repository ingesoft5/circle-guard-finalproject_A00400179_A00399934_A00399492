def call(List<String> services) {
    if (!services) {
        return
    }
    try {
        cgGradle('integrationTest', services)
    } finally {
        junit allowEmptyResults: true, testResults: 'services/*/build/test-results/integrationTest/*.xml'
    }
}
