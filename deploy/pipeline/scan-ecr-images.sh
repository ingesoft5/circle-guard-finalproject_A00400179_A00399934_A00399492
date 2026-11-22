#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$ROOT_DIR/deploy/lib.sh"

VERSION=${1:?uso: scan-ecr-images.sh <semver>}
cg_validate_semver "$VERSION"

SEVERITY=${IMAGE_SCAN_SEVERITY:-CRITICAL}
AWS_REGION=${AWS_REGION:-us-east-2}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY=${ECR_REGISTRY:-$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com}
REPORT_DIR=$ROOT_DIR/deploy/pipeline-reports
mkdir -p "$REPORT_DIR"
command -v trivy >/dev/null 2>&1 || cg_die "trivy no está instalado en este agente."

blocked=0
errors=0
for name in "${CG_SERVICES[@]}" "$CG_WEB_SERVICE"; do
  report="$REPORT_DIR/trivy-image-$name.txt"
  cg_info "==> Trivy image $name:$VERSION (umbral: $SEVERITY)"
  rc=0
  trivy image --no-progress --scanners vuln --severity "$SEVERITY" --exit-code 10 \
    --format table --output "$report" "$ECR_REGISTRY/$name:$VERSION" || rc=$?
  case "$rc" in
    0) cg_info "OK $name" ;;
    10) cg_info "BLOQUEADA $name"; tail -n 40 "$report"; blocked=$((blocked + 1)) ;;
    *) cg_info "ERROR $name (código $rc)"; errors=$((errors + 1)) ;;
  esac
done

[[ "$errors" == 0 ]] || cg_die "$errors escaneos no se pudieron completar. Un escaneo que no corrió no cuenta como aprobado."
[[ "$blocked" == 0 ]] || cg_die "$blocked imágenes con hallazgos $SEVERITY. Despliegue detenido."
cg_info "Trivy imágenes sin hallazgos bloqueantes"
