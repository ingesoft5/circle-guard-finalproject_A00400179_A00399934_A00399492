#!/usr/bin/env bash
# HU-15 · OWASP ZAP baseline scan of the web client, with the blocking gate of security/zap/evaluate-zap.sh.
#
#   security/zap/run-zap-baseline.sh --target http://web:8080 --network circleguard-hu14val_circleguard
#   security/zap/run-zap-baseline.sh --target https://dev.example.org --out security/reports/zap
#
# Options:
#   --target URL     web client to scan (required). Controlled environments only (local, dev, stage): never production.
#   --network NAME   Docker network to join, when the target is a Compose stack (default: none)
#   --out DIR        report directory (default: $SECURITY_REPORT_DIR/zap, not versioned)
#   --env NAME       environment label, local | dev | stage (default: local). Anything else, prod above all, is refused.
#
# The baseline scan is PASSIVE: ZAP spiders the site for a short time and inspects the responses, it sends no attack payloads.
# It does not replace a penetration test. Reports: zap-report.html (human), zap-report.json (machine), zap-report.md, gate.txt.
# The ZAP image and the threshold are pinned in security/policy.env. The container runs without root and writes to a Docker volume
# that is streamed back, so it also works when the Docker daemon is remote (Jenkins with Docker-in-Docker).
# Exit code: 0 = nothing blocks; 1 = an alert reaches the threshold; 2 = the scan could not be completed.
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=security/policy.env
source "$ROOT_DIR/security/policy.env"

TARGET="" NETWORK="" OUT="" ENV_LABEL=local
die2() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
while (($#)); do
  case "$1" in
    --target) TARGET=${2:?}; shift 2 ;;
    --network) NETWORK=${2:?}; shift 2 ;;
    --out) OUT=${2:?}; shift 2 ;;
    --env) ENV_LABEL=${2:?}; shift 2 ;;
    -h|--help) sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die2 "opción desconocida: $1" ;;
  esac
done
[[ -n "$TARGET" ]] || die2 "--target es obligatorio."
[[ "$TARGET" =~ ^https?:// ]] || die2 "--target debe empezar por http:// o https://."
case "$ENV_LABEL" in local|dev|stage) ;; *) die2 "--env debe ser local, dev o stage: el análisis nunca se ejecuta contra producción." ;; esac
[[ "$ZAP_SPIDER_MINUTES" =~ ^[0-9]+$ ]] || die2 "ZAP_SPIDER_MINUTES debe ser un entero."
command -v docker >/dev/null || die2 "Docker es necesario."

REPORT_DIR=${OUT:-${SECURITY_REPORT_DIR:-security/reports}/zap}
case "$REPORT_DIR" in /*) ;; *) REPORT_DIR="$ROOT_DIR/$REPORT_DIR" ;; esac
mkdir -p "$REPORT_DIR"
NET_ARGS=(); [[ -z "$NETWORK" ]] || NET_ARGS=(--network "$NETWORK")
volume="hu15-zap-$$-$RANDOM"
cleanup() { docker volume rm -f "$volume" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "ZAP: $ZAP_IMAGE"
echo "Objetivo: $TARGET ($ENV_LABEL) · rastreo: ${ZAP_SPIDER_MINUTES} min · umbral que bloquea: $ZAP_BLOCK_RISK"
docker volume create "$volume" >/dev/null
# The ZAP user (uid 1000) must be able to write in the fresh volume.
docker run --rm -v "$volume":/zap/wrk --user root --entrypoint sh "$ZAP_IMAGE" -c 'chown 1000:1000 /zap/wrk' >/dev/null

# Rules file (security/zap/zap-baseline.conf) is streamed into the volume; -I: warnings do not fail the scan, the gate decides.
docker run --rm -i -v "$volume":/zap/wrk --user root --entrypoint sh "$ZAP_IMAGE" -c 'cat > /zap/wrk/zap-baseline.conf && chown 1000:1000 /zap/wrk/zap-baseline.conf' \
  <"$ROOT_DIR/security/zap/zap-baseline.conf"

zap_rc=0
docker run --rm "${NET_ARGS[@]}" -v "$volume":/zap/wrk "$ZAP_IMAGE" zap-baseline.py \
  -t "$TARGET" -c zap-baseline.conf -m "$ZAP_SPIDER_MINUTES" -I \
  -r zap-report.html -J zap-report.json -w zap-report.md >"$REPORT_DIR/zap-run.log" 2>&1 || zap_rc=$?
# zap-baseline.py: 0 ok, 1 FAIL rules, 2 WARN rules (neutralised by -I), 3 other error.
if ((zap_rc != 0 && zap_rc != 2)); then
  tail -n 15 "$REPORT_DIR/zap-run.log" >&2
  die2 "ZAP no pudo completar el análisis (código $zap_rc)."
fi

docker run --rm -v "$volume":/zap/wrk:ro --entrypoint sh "$ZAP_IMAGE" -c 'tar -C /zap/wrk -cf - zap-report.html zap-report.json zap-report.md' \
  | tar -x -C "$REPORT_DIR" || die2 "no se pudieron recuperar los informes de ZAP."
echo "Informes en $REPORT_DIR"

gate_rc=0
bash "$ROOT_DIR/security/zap/evaluate-zap.sh" "$REPORT_DIR/zap-report.json" | tee "$REPORT_DIR/gate.txt" || gate_rc=${PIPESTATUS[0]}
exit "$gate_rc"
