#!/usr/bin/env bash
# HU-14 · Vulnerability scan of the Java dependencies of every CircleGuard service, with the same severity gate as
# the image scan (security/policy.env).
#
# How it works:
#   1. Gradle resolves the runtime dependencies of each service (the ones inside its bootJar) through the init script
#      security/gradle/dependency-sbom.init.gradle.kts and writes a CycloneDX SBOM per service. No build.gradle.kts is
#      modified: the init script is only passed on the command line.
#   2. Trivy matches every component against its vulnerability database (security/scan-images.sh --sbom).
#   3. The gate counts CRITICAL/HIGH findings per service. Exit code: 0 = nothing blocks, 1 = a service exceeds the
#      threshold, 2 = a step failed (never reported as a pass).
#
# Usage:
#   security/scan-dependencies.sh                 all services
#   security/scan-dependencies.sh <service>...    only those (for example circleguard-auth-service)
#   CG_SKIP_GRADLE=true security/scan-dependencies.sh   reuse the SBOMs already generated
# Requirements: JDK 21 (or a Gradle toolchain), Docker and network access (Maven Central and the Trivy database).
# Outputs in $SECURITY_REPORT_DIR (default security/reports): sbom/<service>.cdx.json, deps_<service>.json/.sarif, summary-*.txt.

set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
# shellcheck source=security/policy.env
source "$ROOT_DIR/security/policy.env"
# shellcheck source=deploy/lib.sh
source "$ROOT_DIR/deploy/lib.sh"

REPORT_DIR="$SECURITY_REPORT_DIR"
case "$REPORT_DIR" in /*) ;; *) REPORT_DIR="$ROOT_DIR/$REPORT_DIR" ;; esac
SBOM_DIR="$REPORT_DIR/sbom"
GRADLE=${CG_GRADLE:-./gradlew}
PROJECT_CACHE=${CG_GRADLE_PROJECT_CACHE:-${HOME:-/tmp}/.cache/circleguard-security-gradle}

SERVICES=("$@")
((${#SERVICES[@]})) || SERVICES=("${CG_SERVICES[@]}")
mkdir -p "$SBOM_DIR"

if [[ "${CG_SKIP_GRADLE:-false}" != "true" ]]; then
  tasks=()
  for service in "${SERVICES[@]}"; do tasks+=(":services:$service:cgDependencySbom"); done
  cg_info "==> Gradle: resolving the runtime dependencies of ${#SERVICES[@]} service(s)"
  "$GRADLE" --no-daemon --console=plain -q --project-cache-dir "$PROJECT_CACHE" \
    --init-script "$ROOT_DIR/security/gradle/dependency-sbom.init.gradle.kts" "${tasks[@]}" >&2
fi

args=()
for service in "${SERVICES[@]}"; do
  sbom="$ROOT_DIR/services/$service/build/security/sbom.cdx.json"
  [[ -s "$sbom" ]] || cg_die "No se generó el SBOM de $service ($sbom)."
  cp "$sbom" "$SBOM_DIR/$service.cdx.json"
  args+=(--sbom "$SBOM_DIR/$service.cdx.json=$service")
done

exec bash "$ROOT_DIR/security/scan-images.sh" "${args[@]}" --class own
