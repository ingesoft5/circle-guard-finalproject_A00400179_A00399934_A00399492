def call(Map cfg = [:]) {
    List<String> all = (cfg.services ?: []) as List<String>
    String mode = (cfg.mode ?: 'changed').toString()
    String base = (cfg.baseRef ?: 'origin/dev').toString()
    if (mode == 'all') {
        return all
    }
    String prev = env.GIT_PREVIOUS_SUCCESSFUL_COMMIT ?: ''
    String ref = prev ? prev : base
    String diffCmd = "git diff --name-only ${ref}...HEAD 2>/dev/null || git diff --name-only HEAD~1 HEAD 2>/dev/null || true"
    List<String> files = sh(script: diffCmd, returnStdout: true).trim().split('\n').findAll { it }.collect { it.trim() }
    if (files.isEmpty()) {
        return all
    }
    boolean global = files.any { f ->
        f == 'build.gradle.kts' || f == 'settings.gradle.kts' || f == 'gradle.properties' ||
        f.startsWith('gradle/') || f == 'Jenkinsfile' || f.startsWith('jenkins/')
    }
    if (global) {
        return all
    }
    return all.findAll { svc -> files.any { it.startsWith("services/${svc}/") } }
}
