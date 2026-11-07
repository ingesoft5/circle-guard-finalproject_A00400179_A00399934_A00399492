def call(Map cfg = [:]) {
    List<String> services = (cfg.services ?: []) as List<String>
    String installation = (cfg.installation ?: 'sonarqube').toString()
    int minutes = (cfg.timeoutMinutes ?: 10) as int
    if (!services) {
        return
    }
    String targets = services.collect { ":services:${it}:sonar" }.join(' ')
    withSonarQubeEnv(installation) {
        sh "chmod +x ./gradlew && ./gradlew ${targets} -Dsonar.projectKey=circleguard -Dsonar.projectName=CircleGuard --no-daemon --console=plain"
    }
    timeout(time: minutes, unit: 'MINUTES') {
        def gate = waitForQualityGate()
        if (gate.status != 'OK') {
            error "Quality gate de SonarQube fallido: ${gate.status}"
        }
    }
}
