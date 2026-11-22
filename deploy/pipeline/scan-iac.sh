#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$ROOT_DIR/deploy/lib.sh"

SEVERITY=${IAC_SCAN_SEVERITY:-CRITICAL}
REPORT_DIR=$ROOT_DIR/deploy/pipeline-reports
mkdir -p "$REPORT_DIR"
command -v trivy >/dev/null 2>&1 || cg_die "trivy no está instalado en este agente."

failed=0
for target in infra/terraform deploy/k8s; do
  name=${target//\//-}
  report="$REPORT_DIR/trivy-iac-$name.txt"
  cg_info "==> Trivy config en $target (umbral: $SEVERITY)"
  rc=0
  trivy config --severity "$SEVERITY" --skip-dirs '**/.terraform' --exit-code 10 \
    --format table --output "$report" "$ROOT_DIR/$target" || rc=$?
  cat "$report"
  case "$rc" in
    0) cg_info "OK $target" ;;
    10) cg_info "BLOQUEADO $target"; failed=1 ;;
    *) cg_die "Trivy falló en $target (código $rc)" ;;
  esac
done

[[ "$failed" == 0 ]] || cg_die "Trivy IaC: hay hallazgos $SEVERITY. Promoción detenida."
cg_info "Trivy IaC sin hallazgos bloqueantes"
