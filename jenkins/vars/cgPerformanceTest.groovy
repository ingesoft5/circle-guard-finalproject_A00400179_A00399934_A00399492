/**
 * HU-15 · Locust load test (access validation and questionnaire submission) of a controlled environment, compared with the
 * declared objectives of tests/performance/targets.json.
 *
 *   cgPerformanceTest(host: 'http://web:8080', env: 'dev', credentialsId: 'perf-test-user', steps: '10 50 100', duration: '5m')
 *
 * The test user comes from a Jenkins "username with password" credential (never from the repository); it is passed through the
 * environment of the script and is masked in the log. Production is refused by the script: only env local, dev or stage.
 * Results (Locust CSV and HTML, SVG charts, evaluation.md/json) are archived from tests/performance/results/<build>/.
 * With enforce: true (default false) an objective that is not met fails the build; otherwise the build is marked UNSTABLE.
 * A run that could not execute, or an objective that was not measured, always fails the build.
 */
def call(Map cfg = [:]) {
    String host = (cfg.host ?: '').toString().trim()
    String envName = (cfg.env ?: 'dev').toString()
    String credentialsId = (cfg.credentialsId ?: '').toString()
    String steps = (cfg.steps ?: '10 50 100').toString()
    String duration = (cfg.duration ?: '5m').toString()
    String network = (cfg.network ?: '').toString().trim()
    boolean enforce = (cfg.enforce == null) ? false : (cfg.enforce as boolean)
    if (!host || !credentialsId) {
        error('cgPerformanceTest needs host and credentialsId')
    }
    String out = "tests/performance/results/build-${env.BUILD_NUMBER ?: 'local'}"
    String command = "bash ./tests/performance/run-perf.sh --host '${host}' --steps '${steps}' --duration '${duration}' --out '${out}'"
    if (network) {
        command += " --network '${network}'"
    }
    if (enforce) {
        command += ' --enforce'
    }

    int rc = 0
    withEnv(["PERF_TARGET_ENV=${envName}"]) {
        withCredentials([usernamePassword(credentialsId: credentialsId, usernameVariable: 'PERF_USERNAME', passwordVariable: 'PERF_PASSWORD')]) {
            rc = sh(returnStatus: true, script: command)
        }
    }
    archiveArtifacts artifacts: "${out}/**", allowEmptyArchive: true
    if (rc == 0) {
        if (fileExists("${out}/evaluation.json") && readFile("${out}/evaluation.json").contains('"NOT MET"')) {
            unstable('Performance test (report mode): at least one declared objective was not met; see evaluation.md in the archived results.')
        } else {
            echo 'Performance test: every declared objective was met.'
        }
        return
    }
    if (rc == 1) {
        error('Performance gate: a declared objective was not met (enforce mode); see evaluation.md in the archived results.')
    }
    error("Performance test could not be completed (exit code ${rc}). A test that did not run is not a pass.")
}
