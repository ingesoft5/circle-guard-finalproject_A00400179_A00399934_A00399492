#!/usr/bin/env bash
# Builds the nine CircleGuard images (8 services + web client) with a semantic tag.
# Usage:
#   ./deploy/build-images.sh 1.0.0
#   IMAGE_REGISTRY=localhost:5000 ./deploy/build-images.sh 1.0.0
#   NO_CACHE=1 PLATFORM=linux/amd64 ./deploy/build-images.sh 1.0.0
# The tag 'latest' and non-semver tags are rejected before Docker runs.
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
# shellcheck source=deploy/lib.sh
source "$ROOT_DIR/deploy/lib.sh"

VERSION=${1:-${IMAGE_TAG:-}}
cg_validate_semver "$VERSION"
export IMAGE_REGISTRY=${IMAGE_REGISTRY:-localhost:5000}
export IMAGE_NAMESPACE=${IMAGE_NAMESPACE:-circleguard}
cg_require_docker

REVISION=$(git rev-parse HEAD 2>/dev/null || printf 'unknown')
CREATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LOG_DIR="$ROOT_DIR/deploy/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/build-$VERSION-$(date -u +%Y%m%dT%H%M%SZ).log"
exec > >(tee -a "$LOG_FILE") 2>&1

PLATFORM_ARGS=()
if [[ -n "${PLATFORM:-}" ]]; then
  PLATFORM_ARGS=(--platform "$PLATFORM")
fi
CACHE_ARGS=()
if [[ "${NO_CACHE:-0}" == "1" ]]; then
  CACHE_ARGS=(--no-cache)
fi

cg_info "CircleGuard image build"
cg_info "  version:   $VERSION"
cg_info "  registry:  $IMAGE_REGISTRY/$IMAGE_NAMESPACE"
cg_info "  revision:  $REVISION"
cg_info "  created:   $CREATED"
cg_info "  log:       $LOG_FILE"
cg_info ""

for service in "${CG_SERVICES[@]}"; do
  image=$(cg_image_ref "$service" "$VERSION")
  cg_info "==> Building $image"
  docker build \
    "${PLATFORM_ARGS[@]}" \
    "${CACHE_ARGS[@]}" \
    --pull \
    --build-arg VERSION="$VERSION" \
    --build-arg REVISION="$REVISION" \
    --build-arg CREATED="$CREATED" \
    -f "services/$service/Dockerfile" \
    -t "$image" \
    .
done

WEB_IMAGE=$(cg_image_ref "$CG_WEB_SERVICE" "$VERSION")
cg_info "==> Building $WEB_IMAGE"
docker build \
  "${PLATFORM_ARGS[@]}" \
  "${CACHE_ARGS[@]}" \
  --pull \
  --build-arg VERSION="$VERSION" \
  --build-arg REVISION="$REVISION" \
  --build-arg CREATED="$CREATED" \
  -f mobile/Dockerfile \
  -t "$WEB_IMAGE" \
  mobile

cg_info ""
cg_info "Imágenes construidas:"
for name in "${CG_SERVICES[@]}" "$CG_WEB_SERVICE"; do
  image=$(cg_image_ref "$name" "$VERSION")
  docker image inspect --format '  {{json .RepoTags}} {{.Id}}' "$image"
done
cg_info ""
cg_info "Siguiente paso: ./deploy/publish-images.sh $VERSION"
