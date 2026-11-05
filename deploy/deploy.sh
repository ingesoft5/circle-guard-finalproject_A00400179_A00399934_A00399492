#!/usr/bin/env bash
# Deploys a semantic version to an environment (HU-06).
# Local:
#   ./deploy/deploy.sh dev 1.0.0
# Remote over SSH (environment host prepared by HU-01):
#   DEPLOY_MODE=ssh DEPLOY_HOST=ubuntu@10.20.10.10 \
#     DEPLOY_PATH=/opt/circleguard/circleguard \
#     ./deploy/deploy.sh stage 1.0.0
# The version is recorded in deploy/releases/<env>.json after a successful deployment.
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
# shellcheck source=deploy/lib.sh
source "$ROOT_DIR/deploy/lib.sh"

ENV_NAME=${1:-}
VERSION=${2:-}
cg_validate_env "$ENV_NAME"
if [[ "$VERSION" == "current" ]]; then
  VERSION=$(cg_current_version "$ENV_NAME")
fi
cg_validate_semver "$VERSION"

export IMAGE_REGISTRY=${IMAGE_REGISTRY:-localhost:5000}
export IMAGE_NAMESPACE=${IMAGE_NAMESPACE:-circleguard}
EVENT=${EVENT:-deploy}
case "$EVENT" in
  deploy|rollback|promote|hotfix) ;;
  *) cg_die "Evento inválido '$EVENT'. Use deploy, rollback, promote o hotfix." ;;
esac
ACTOR=${ACTOR:-${USER:-jenkins}}
DEPLOY_MODE=${DEPLOY_MODE:-local}
DEPLOY_PATH=${DEPLOY_PATH:-/opt/circleguard/circleguard}
HOST_VAR="DEPLOY_HOST_$(printf '%s' "$ENV_NAME" | tr '[:lower:]' '[:upper:]')"
DEPLOY_HOST=${DEPLOY_HOST:-${!HOST_VAR:-}}

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new)
if [[ -n "${DEPLOY_SSH_KEY:-}" ]]; then
  SSH_OPTS+=(-i "$DEPLOY_SSH_KEY")
fi

cg_info "CircleGuard deploy"
cg_info "  environment: $ENV_NAME"
cg_info "  version:     $VERSION"
cg_info "  registry:    $IMAGE_REGISTRY/$IMAGE_NAMESPACE"
cg_info "  mode:        $DEPLOY_MODE"

if [[ "$DEPLOY_MODE" == "ssh" ]]; then
  [[ -n "$DEPLOY_HOST" ]] || cg_die "DEPLOY_MODE=ssh requiere DEPLOY_HOST o $HOST_VAR."
  cg_info "  host:        $DEPLOY_HOST"
  ssh "${SSH_OPTS[@]}" "$DEPLOY_HOST" \
    "cd $(printf '%q' "$DEPLOY_PATH") && IMAGE_TAG=$(printf '%q' "$VERSION") IMAGE_REGISTRY=$(printf '%q' "$IMAGE_REGISTRY") IMAGE_NAMESPACE=$(printf '%q' "$IMAGE_NAMESPACE") CG_ENV_FILE=$(printf '%q' "/opt/circleguard/$ENV_NAME/.env") ./deploy/compose-up.sh $(printf '%q' "$ENV_NAME")"
else
  IMAGE_TAG="$VERSION" \
    IMAGE_REGISTRY="$IMAGE_REGISTRY" \
    IMAGE_NAMESPACE="$IMAGE_NAMESPACE" \
    CG_ENV_FILE="${CG_ENV_FILE:-}" \
    ./deploy/compose-up.sh "$ENV_NAME"
fi

./deploy/record-release.sh "$ENV_NAME" "$VERSION" "$EVENT" "$ACTOR"

if [[ "$EVENT" == "rollback" ]]; then
  ./deploy/notify.sh rollback "$ENV_NAME" "$VERSION" "Rollback aplicado" || true
else
  ./deploy/notify.sh success "$ENV_NAME" "$VERSION" "Despliegue completado" || true
fi

cg_info "OK: $ENV_NAME desplegado en $VERSION"
