/**
 * HU-14 · Runs one security scan of the security/ directory, archives its reports and enforces its gate.
 *
 *   cgSecurityScan(kind: 'secrets')                         security/scan-secrets-ci.sh
 *   cgSecurityScan(kind: 'dependencies')                    security/scan-dependencies.sh   (Java libraries of the 8 services)
 *   cgSecurityScan(kind: 'iac')                             security/scan-iac.sh            (Terraform, Kubernetes manifests, RBAC)
 *   cgSecurityScan(kind: 'images', version: env.VERSION)    security/scan-images.sh --own <version> --third-party
 *   cgSecurityScan(kind: 'images', version: '1.2.3', enforce: false)   report only: findings mark the build UNSTABLE instead of failing it
 *
 * The scripts return 0 (nothing blocks), 1 (a blocking finding) or 2 (the scan could not complete). Exit 2 ALWAYS fails the build:
 * a scan that did not run is never a pass. Exit 1 fails the build when `enforce` is true (the default), which is what stops the
 * promotion: the stages that publish and deploy come after the scans in the Jenkinsfile.
 *
 * Reports are archived from security/reports/ (JSON, SARIF and a summary per scan).
 */
def call(Map cfg = [:]) {
    String kind = (cfg.kind ?: '').toString()
    boolean enforce = (cfg.enforce == null) ? true : (cfg.enforce as boolean)
    String version = (cfg.version ?: env.VERSION ?: '').toString()

    String command
    switch (kind) {
        case 'secrets':
            command = 'bash ./security/scan-secrets-ci.sh'
            break
        case 'dependencies':
            command = 'bash ./security/scan-dependencies.sh'
            break
        case 'iac':
            command = 'bash ./security/scan-iac.sh'
            break
        case 'images':
            if (!version) {
                error('cgSecurityScan(kind: images) needs a version (cfg.version or env.VERSION)')
            }
            command = "bash ./security/scan-images.sh --own '${version}' --third-party"
            break
        default:
            error("cgSecurityScan: unknown kind '${kind}' (use secrets, dependencies, iac or images)")
    }

    int rc = sh(returnStatus: true, script: command)
    archiveArtifacts artifacts: 'security/reports/**', allowEmptyArchive: true, fingerprint: true

    if (rc == 0) {
        echo "Security scan '${kind}': no blocking finding."
        return
    }
    if (rc == 1) {
        if (enforce) {
            error("Security gate '${kind}': a finding exceeds the threshold. The promotion is stopped; see the archived reports.")
        }
        unstable("Security scan '${kind}': findings exceed the threshold (report mode, the build is not failed).")
        return
    }
    error("Security scan '${kind}' could not be completed (exit code ${rc}). A scan that did not run is not a pass.")
}
