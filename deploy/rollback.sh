#!/usr/bin/env bash
# Rolls an environment back to a previously published semantic version (HU-06).
# Usage:
#   IMAGE_REGISTRY=localhost:5000 ./deploy/rollback.sh dev 1.0.0
#   DEPLOY_MODE=k8s ./deploy/rollback.sh dev 1.0.0
# The target version must be different from the current one and its images must
# exist in the registry (or locally for local deployments).
set -Eeuo pipefail
trap 'printf "rollback.sh: fallo en la línea %s\n" "$LINENO" >&2' ERR

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

CURRENT=$(cg_current_version_optional "$ENV_NAME" 2>/dev/null || true)
[[ "$VERSION" != "$CURRENT" ]] || cg_die "La versión $VERSION ya está desplegada en $ENV_NAME."

if [[ "$DEPLOY_MODE" == "k8s" ]]; then
  command -v aws >/dev/null 2>&1 || cg_die "DEPLOY_MODE=k8s requiere AWS CLI."
  command -v kubectl >/dev/null 2>&1 || cg_die "DEPLOY_MODE=k8s requiere kubectl."

  AWS_REGION=${AWS_REGION:-us-east-2}
  if [[ -z "${KUBECONFIG:-}" ]]; then
    KUBECONFIG=$(mktemp)
    chmod 600 "$KUBECONFIG"
    export KUBECONFIG
    trap 'rm -f "$KUBECONFIG"' EXIT
    aws ssm get-parameter --region "$AWS_REGION" --name "/circleguard/$ENV_NAME/kubeconfig" \
      --with-decryption --query Parameter.Value --output text > "$KUBECONFIG"
  fi

  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  ECR_REGISTRY=${ECR_REGISTRY:-$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com}
  for name in "${CG_SERVICES[@]}" "$CG_WEB_SERVICE"; do
    aws ecr describe-images --region "$AWS_REGION" --repository-name "$name" \
      --image-ids imageTag="$VERSION" >/dev/null 2>&1 \
      || cg_die "La imagen $name:$VERSION no existe en ECR."
  done

  cg_info "Rollback K8s de $ENV_NAME: ${CURRENT:-sin versión} -> $VERSION"
  AWS_REGION="$AWS_REGION" ECR_REGISTRY="$ECR_REGISTRY" \
    ./deploy/k8s/deploy.sh "$ENV_NAME" "$VERSION"
  RESULT=success ./deploy/record-release.sh "$ENV_NAME" "$VERSION" rollback "${USER:-jenkins}"
  cg_info "Rollback K8s registrado en deploy/releases/$ENV_NAME.json"
  exit 0
fi

if [[ "$DEPLOY_MODE" == "ssh" ]]; then
  cg_info "La verificación de imágenes se delega al host remoto."
elif command -v docker >/dev/null 2>&1; then
  for name in "${CG_SERVICES[@]}" "$CG_WEB_SERVICE"; do
    image=$(cg_image_ref "$name" "$VERSION")
    # Local deployments may already have the image in the daemon even when the
    # registry is not reachable from this host (or requires a separate login).
    if ! docker manifest inspect "$image" >/dev/null 2>&1 \
       && ! docker image inspect "$image" >/dev/null 2>&1; then
      cg_die "La imagen $image no está disponible para rollback."
    fi
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
