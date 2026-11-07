def call(Map cfg = [:]) {
    List<String> services = (cfg.services ?: []) as List<String>
    String url = (cfg.nexusUrl ?: '').toString().trim()
    String repo = (cfg.repository ?: 'circleguard-artifacts').toString()
    String version = (cfg.version ?: env.BUILD_NUMBER).toString()
    String credentialsId = (cfg.credentialsId ?: 'nexus-credentials').toString()
    if (!services) {
        return
    }
    if (!url) {
        echo 'NEXUS_URL vacío: publicación omitida, los jar quedan archivados en Jenkins'
        return
    }
    withCredentials([usernamePassword(credentialsId: credentialsId, usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASSWORD')]) {
        services.each { svc ->
            sh """
                set -e
                for jar in services/${svc}/build/libs/*.jar; do
                  [ -e "\$jar" ] || continue
                  name=\$(basename "\$jar")
                  curl -fsS --user "\$NEXUS_USER:\$NEXUS_PASSWORD" --upload-file "\$jar" "${url}/repository/${repo}/${svc}/${version}/\$name"
                done
            """
        }
    }
}
