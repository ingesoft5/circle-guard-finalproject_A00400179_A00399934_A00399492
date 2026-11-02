#!/usr/bin/env bash
# Verifies the immutable-image criteria on the local Docker daemon (HU-02):
# non-root user, semantic version label, image ID and registry digests.
# Usage:
#   ./deploy/verify-images.sh 1.0.0
#   ./deploy/verify-images.sh --evidence 1.0.0   # also writes docs/evidencias/hu-02/02-docker-inspect.txt
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
# shellcheck source=deploy/lib.sh
source "$ROOT_DIR/deploy/lib.sh"

EVIDENCE=0
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --evidence) EVIDENCE=1 ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done
VERSION=${POSITIONAL[0]:-${IMAGE_TAG:-}}
cg_validate_semver "$VERSION"
export IMAGE_REGISTRY=${IMAGE_REGISTRY:-localhost:5000}
export IMAGE_NAMESPACE=${IMAGE_NAMESPACE:-circleguard}
cg_require_docker

if [[ "$EVIDENCE" == "1" ]]; then
  mkdir -p "$ROOT_DIR/docs/evidencias/hu-02"
  exec > >(tee "$ROOT_DIR/docs/evidencias/hu-02/02-docker-inspect.txt") 2>&1
  cg_info "Evidencia generada por deploy/verify-images.sh el $(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi

failures=0
cg_info "Imágenes de CircleGuard versión $VERSION"
for name in "${CG_SERVICES[@]}" "$CG_WEB_SERVICE"; do
  image=$(cg_image_ref "$name" "$VERSION")
  if ! docker image inspect "$image" >/dev/null 2>&1; then
    cg_info "  FALTA  $image"
    failures=$((failures + 1))
    continue
  fi
  line=$(docker image inspect --format \
    'user={{.Config.User}} version={{index .Config.Labels "org.opencontainers.image.version"}} revision={{index .Config.Labels "org.opencontainers.image.revision"}} id={{.Id}} digests={{json .RepoDigests}}' \
    "$image")
  cg_info "  OK     $image"
  cg_info "         $line"
  user=${line#user=}
  user=${user%% *}
  if [[ -z "$user" || "$user" == "root" || "$user" == "0" || "$user" == "0:0" ]]; then
    cg_info "         ERROR: la imagen se ejecuta como root ('$user')."
    failures=$((failures + 1))
  fi
  if [[ "$line" != *"version=$VERSION"* ]]; then
    cg_info "         ERROR: la etiqueta OCI de versión no coincide con $VERSION."
    failures=$((failures + 1))
  fi
done

cg_info ""
docker image ls --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}' \
  | grep -E 'REPOSITORY|circleguard' || true

if ((failures > 0)); then
  cg_die "$failures comprobación(es) fallaron."
fi
cg_info ""
cg_info "OK: 9 imágenes con versión semántica y usuario no root."
