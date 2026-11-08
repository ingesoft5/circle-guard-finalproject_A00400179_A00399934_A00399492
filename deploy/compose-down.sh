#!/usr/bin/env bash
# Stops a CircleGuard environment. Volumes are preserved by default; set
# CG_DOWN_VOLUMES=1 to delete them as well (used by the sequential CI promotion
# so dev/stage do not keep ~2 GB of data each on the 30 GB CI host).
# Usage: ./deploy/compose-down.sh dev
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_NAME=${1:-}
[[ -n "$ENV_NAME" ]] || { printf 'Uso: %s <dev|stage|prod>\n' "$0" >&2; exit 2; }

# shellcheck source=deploy/compose-env.sh
source "$ROOT_DIR/deploy/compose-env.sh" "$ENV_NAME"
# shellcheck source=deploy/lib.sh
source "$ROOT_DIR/deploy/lib.sh"
cg_require_docker

DOWN_ARGS=(down --remove-orphans)
if [[ "${CG_DOWN_VOLUMES:-0}" == "1" ]]; then
  DOWN_ARGS+=(--volumes)
fi
"${CG_COMPOSE[@]}" "${DOWN_ARGS[@]}"
if [[ "${CG_DOWN_VOLUMES:-0}" == "1" ]]; then
  printf 'Contenedores y volúmenes del ambiente %s eliminados.\n' "$ENV_NAME"
else
  printf 'Contenedores detenidos. Los volúmenes se conservan.\n'
fi
