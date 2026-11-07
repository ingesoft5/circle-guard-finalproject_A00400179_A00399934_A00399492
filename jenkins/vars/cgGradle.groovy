def call(String tasks, List<String> services, String extra = '') {
    if (!services) {
        echo 'Sin servicios para ejecutar'
        return
    }
    List<String> names = tasks.tokenize(' ')
    String targets = services.collectMany { svc -> names.collect { t -> ":services:${svc}:${t}" } }.join(' ')
    sh "chmod +x ./gradlew && ./gradlew ${targets} ${extra} --continue --no-daemon --console=plain"
}
