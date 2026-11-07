def call(String status, String message) {
    try {
        withCredentials([string(credentialsId: 'discord-webhook', variable: 'DISCORD_WEBHOOK_URL')]) {
            String text = "[CircleGuard CI] ${status.toUpperCase()} ${env.JOB_NAME} #${env.BUILD_NUMBER} - ${message} ${env.BUILD_URL}"
            writeFile file: '.notify.json', text: groovy.json.JsonOutput.toJson([content: text])
            sh 'curl -fsS -H "Content-Type: application/json" -d @.notify.json "$DISCORD_WEBHOOK_URL" || true; rm -f .notify.json'
        }
    } catch (Exception exc) {
        echo "Notificación omitida: ${exc.message}"
    }
}
