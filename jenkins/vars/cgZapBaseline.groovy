/**
 * HU-15 · OWASP ZAP baseline scan of the web client of a controlled environment, with a blocking gate.
 *
 *   cgZapBaseline(target: params.E2E_URL_DEV, env: 'dev')
 *   cgZapBaseline(target: 'http://web:8080', env: 'local', network: 'circleguard_default', enforce: false)
 *
 * It runs security/zap/run-zap-baseline.sh, which returns 0 (nothing reaches the threshold ZAP_BLOCK_RISK of security/policy.env),
 * 1 (an alert reaches it) or 2 (the scan could not be completed). Exit 2 ALWAYS fails the build: a scan that did not run is not a pass.
 * Exit 1 fails the build when `enforce` is true (the default), which stops the promotion. With enforce: false the build is UNSTABLE.
 * Reports (HTML, JSON, Markdown, gate summary) are archived from security/reports/zap/ and the HTML is published as "OWASP ZAP".
 * Production is refused by the script: only env local, dev or stage.
 */
def call(Map cfg = [:]) {
    String target = (cfg.target ?: '').toString().trim()
    String envName = (cfg.env ?: 'dev').toString()
    String network = (cfg.network ?: '').toString().trim()
    boolean enforce = (cfg.enforce == null) ? true : (cfg.enforce as boolean)
    if (!target) {
        error('cgZapBaseline needs a target URL (cfg.target)')
    }
    String command = "bash ./security/zap/run-zap-baseline.sh --target '${target}' --env '${envName}'"
    if (network) {
        command += " --network '${network}'"
    }

    int rc = sh(returnStatus: true, script: command)
    archiveArtifacts artifacts: 'security/reports/zap/**', allowEmptyArchive: true, fingerprint: true
    publishHTML(target: [reportDir: 'security/reports/zap', reportFiles: 'zap-report.html', reportName: 'OWASP ZAP',
                         keepAll: true, alwaysLinkToLastBuild: true, allowMissing: true])

    if (rc == 0) {
        echo 'OWASP ZAP baseline: no alert reaches the blocking threshold.'
        return
    }
    if (rc == 1) {
        if (enforce) {
            error('OWASP ZAP gate: an alert reaches the blocking threshold. The promotion is stopped; see the archived report.')
        }
        unstable('OWASP ZAP baseline: alerts reach the threshold (report mode, the build is not failed).')
        return
    }
    error("OWASP ZAP baseline could not be completed (exit code ${rc}). A scan that did not run is not a pass.")
}
