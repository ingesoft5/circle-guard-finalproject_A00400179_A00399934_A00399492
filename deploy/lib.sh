#!/usr/bin/env bash
# Shared helpers for the CircleGuard image and Compose scripts (HU-02).
# Portable Bash: works in WSL, Linux and Git Bash; no WSL-only paths.
set -Eeuo pipefail

CG_SERVICES=(
  circleguard-auth-service
  circleguard-identity-service
  circleguard-dashboard-service
  circleguard-file-service
  circleguard-form-service
  circleguard-gateway-service
  circleguard-notification-service
  circleguard-promotion-service
)
CG_WEB_SERVICE=circleguard-web
CG_REPO_ROOT=${CG_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
CG_GITHUB_URL=${CG_GITHUB_URL:-https://github.com/ingesoft5/circle-guard-finalproject_A00400179_A00399934_A00399492}
CG_RELEASES_DIR=${CG_RELEASES_DIR:-${HOME:-/tmp}/.circleguard/releases}

cg_die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
cg_info() { printf '%s\n' "$*"; }

cg_validate_env() {
  case "${1:-}" in
    dev|stage|prod) ;;
    *) cg_die "Ambiente inválido ('${1:-}'). Use dev, stage o prod." ;;
  esac
}

cg_utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
cg_short_commit() { git -C "$CG_REPO_ROOT" rev-parse --short HEAD 2>/dev/null || printf 'unknown'; }

cg_current_version() {
  local env_name=${1:?Falta el ambiente}
  local version=""
  local json
  for json in \
    "$CG_RELEASES_DIR/$env_name.json" \
    "$CG_REPO_ROOT/deploy/releases/$env_name.json"; do
    if [[ -f "$json" ]]; then
      version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$json" | head -n 1)
      [[ -n "$version" && "$version" != "null" ]] && break
    fi
  done
  if [[ -z "$version" && -f "/opt/circleguard/$env_name/VERSION" ]]; then
    version=$(head -n 1 "/opt/circleguard/$env_name/VERSION")
  fi
  [[ -n "$version" && "$version" != "null" ]] || cg_die "No hay versión registrada para $env_name."
  printf '%s\n' "$version"
}

cg_validate_semver() {
  local version=${1:-}
  [[ -n "$version" ]] || cg_die "Falta la versión semántica (por ejemplo 1.0.0)."
  [[ "$version" != "latest" ]] || cg_die "El tag 'latest' está prohibido: use una versión semántica (1.0.0)."
  # Docker tags do not allow '+', so semver build metadata is not accepted either.
  if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?$ ]]; then
    cg_die "'$version' no es una versión semántica válida (se espera MAJOR.MINOR.PATCH, por ejemplo 1.0.0)."
  fi
}

cg_require_docker() {
  command -v docker >/dev/null 2>&1 || cg_die "Docker no está disponible. Instale Docker Engine/Desktop y abra una terminal nueva."
  docker info >/dev/null 2>&1 || cg_die "El daemon de Docker no responde. Inicie Docker y vuelva a intentarlo."
  docker compose version >/dev/null 2>&1 || cg_die "Falta el plugin 'docker compose' (Docker Compose v2)."
}

cg_image_ref() {
  local name=$1 version=$2
  printf '%s/%s/%s:%s' \
    "${IMAGE_REGISTRY:?Defina IMAGE_REGISTRY (por ejemplo localhost:5000)}" \
    "${IMAGE_NAMESPACE:-circleguard}" \
    "$name" \
    "$version"
}
