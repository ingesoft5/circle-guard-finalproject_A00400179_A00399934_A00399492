def call(String task, List<String> services, String extra = '') {
    if (!services) {
        echo 'Sin servicios para ejecutar'
        return
    }
    String targets = services.collect { ":services:${it}:${task}" }.join(' ')
    sh "chmod +x ./gradlew && ./gradlew ${targets} ${extra} --continue --no-daemon --console=plain"
}
