def call(List<String> services) {
    if (!services) {
        return
    }
    cgGradle('bootJar', services, '-x test')
    archiveArtifacts artifacts: 'services/*/build/libs/*.jar', fingerprint: true, allowEmptyArchive: true
}
