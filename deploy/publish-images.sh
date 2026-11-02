#!/usr/bin/env bash
# Publishes the nine CircleGuard images to the configured OCI registry (HU-02).
# Usage:
#   ./deploy/publish-images.sh 1.0.0
#   REGISTRY_USER=... REGISTRY_PASSWORD=... ./deploy/publish-images.sh 1.0.0
# The password is sent to 'docker login' through stdin, never as an argument.
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

if [[ -n "${REGISTRY_USER:-}" ]]; then
  [[ -n "${REGISTRY_PASSWORD:-}" ]] || cg_die "REGISTRY_USER está definido pero REGISTRY_PASSWORD no."
  printf '%s' "$REGISTRY_PASSWORD" | docker login "$IMAGE_REGISTRY" \
    --username "$REGISTRY_USER" --password-stdin >/dev/null
  cg_info "Sesión iniciada en $IMAGE_REGISTRY como $REGISTRY_USER"
fi

cg_info "Publicando la versión $VERSION en $IMAGE_REGISTRY/$IMAGE_NAMESPACE"
for name in "${CG_SERVICES[@]}" "$CG_WEB_SERVICE"; do
  image=$(cg_image_ref "$name" "$VERSION")
  cg_info "==> $image"
  docker push "$image"
done

cg_info ""
cg_info "Digests publicados:"
for name in "${CG_SERVICES[@]}" "$CG_WEB_SERVICE"; do
  image=$(cg_image_ref "$name" "$VERSION")
  docker image inspect --format '  {{.RepoTags}} {{json .RepoDigests}}' "$image"
done

# Best-effort registry listing. Nexus may require its REST API instead of /v2/_catalog.
SCHEME=${REGISTRY_SCHEME:-http}
CURL_AUTH=()
if [[ -n "${REGISTRY_USER:-}" && -n "${REGISTRY_PASSWORD:-}" ]]; then
  CURL_AUTH=(-K -)
fi

cg_info ""
cg_info "Catálogo del registro ($SCHEME://$IMAGE_REGISTRY/v2/_catalog):"
if ((${#CURL_AUTH[@]})); then
  printf 'user = "%s:%s"\n' "$REGISTRY_USER" "$REGISTRY_PASSWORD" \
    | curl -fsS "${CURL_AUTH[@]}" "$SCHEME://$IMAGE_REGISTRY/v2/_catalog" || {
        cg_info "  (el registro no expone /v2/_catalog con estas credenciales; use la UI/REST de Nexus)"
      }
else
  curl -fsS "$SCHEME://$IMAGE_REGISTRY/v2/_catalog" || {
    cg_info "  (el registro no expone /v2/_catalog sin autenticación; use la UI/REST de Nexus)"
  }
fi
