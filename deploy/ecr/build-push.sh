#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT_DIR"
source "$ROOT_DIR/deploy/lib.sh"

VERSION=${1:-${IMAGE_TAG:-}}
cg_validate_semver "$VERSION"

AWS_REGION=${AWS_REGION:-us-east-2}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY=${ECR_REGISTRY:-$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com}
REVISION=${REVISION:-$(git rev-parse HEAD 2>/dev/null || printf 'unknown')}
CREATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
export DOCKER_BUILDKIT=1
export BUILDKIT_PROGRESS=plain

aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY" >/dev/null

tag_exists() {
  aws ecr describe-images --region "$AWS_REGION" --repository-name "$1" --image-ids imageTag="$VERSION" >/dev/null 2>&1
}

build_push() {
  local name=$1 dockerfile=$2 context=$3
  local image="$ECR_REGISTRY/$name:$VERSION"
  if tag_exists "$name"; then
    cg_info "==> $name:$VERSION ya existe en ECR, se omite"
    return 0
  fi
  cg_info "==> Construyendo $name:$VERSION"
  docker build \
    --build-arg VERSION="$VERSION" \
    --build-arg REVISION="$REVISION" \
    --build-arg CREATED="$CREATED" \
    -f "$dockerfile" \
    -t "$image" \
    "$context"
  cg_info "==> Publicando $name:$VERSION"
  docker push "$image"
}

for service in "${CG_SERVICES[@]}"; do
  build_push "$service" "services/$service/Dockerfile" .
done
build_push "$CG_WEB_SERVICE" mobile/Dockerfile mobile

cg_info ""
cg_info "Publicado: $VERSION"
for name in "${CG_SERVICES[@]}" "$CG_WEB_SERVICE"; do
  aws ecr describe-images --region "$AWS_REGION" --repository-name "$name" --image-ids imageTag="$VERSION" \
    --query 'imageDetails[0].[repositoryName,imageTags[0],imageDigest]' --output text
done
