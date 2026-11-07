#!/usr/bin/env bash
# Rolls an environment back to a previously published semantic version (HU-06).
# Usage:
#   IMAGE_REGISTRY=localhost:5000 ./deploy/rollback.sh dev 1.0.0
# The target version must be different from the current one and its images must
# exist in the registry (or locally for local deployments).
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
# shellcheck source=deploy/lib.sh
source "$ROOT_DIR/deploy/lib.sh"

ENV_NAME=${1:-}
VERSION=${2:-}
cg_validate_env "$ENV_NAME"
cg_validate_semver "$VERSION"
export IMAGE_REGISTRY=${IMAGE_REGISTRY:-localhost:5000}
export IMAGE_NAMESPACE=${IMAGE_NAMESPACE:-circleguard}
DEPLOY_MODE=${DEPLOY_MODE:-local}

CURRENT=$(cg_current_version "$ENV_NAME" 2>/dev/null || true)
[[ "$VERSION" != "$CURRENT" ]] || cg_die "La versión $VERSION ya está desplegada en $ENV_NAME."

if [[ "$DEPLOY_MODE" == "ssh" ]]; then
  cg_info "La verificación de imágenes se delega al host remoto."
elif command -v docker >/dev/null 2>&1; then
  for name in "${CG_SERVICES[@]}" "$CG_WEB_SERVICE"; do
    image=$(cg_image_ref "$name" "$VERSION")
    docker manifest inspect "$image" >/dev/null 2>&1 \
      || cg_die "La imagen $image no está disponible para rollback."
  done
elif command -v crane >/dev/null 2>&1; then
  for name in "${CG_SERVICES[@]}" "$CG_WEB_SERVICE"; do
    image=$(cg_image_ref "$name" "$VERSION")
    crane manifest "$image" >/dev/null 2>&1 \
      || cg_die "La imagen $image no está disponible para rollback."
  done
else
  cg_die "No hay docker ni crane para verificar las imágenes del rollback."
fi

cg_info "Rollback de $ENV_NAME: ${CURRENT:-sin versión} -> $VERSION"
EVENT=rollback ./deploy/deploy.sh "$ENV_NAME" "$VERSION"

cg_info "Rollback registrado en deploy/releases/$ENV_NAME.json"
