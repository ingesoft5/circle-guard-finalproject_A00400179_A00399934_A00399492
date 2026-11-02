#!/usr/bin/env bash
# Stops a CircleGuard environment. Volumes are preserved on purpose: this script
# never passes -v. To remove data, name the volume explicitly and with approval.
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

"${CG_COMPOSE[@]}" down --remove-orphans
printf 'Contenedores detenidos. Los volúmenes se conservan.\n'
