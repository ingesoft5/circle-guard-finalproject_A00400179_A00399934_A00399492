#!/usr/bin/env bash
# Resolves the Compose invocation for an environment (HU-02). Sourced by
# compose-up.sh / compose-down.sh; it is not executed directly.
#   source deploy/compose-env.sh dev
# Produces the CG_COMPOSE array with the non-secret env file, the secret env
# file(s) and the common + environment Compose files.
set -Eeuo pipefail

CG_ENV=${1:-}
case "$CG_ENV" in
  dev|stage|prod) ;;
  *) printf 'ERROR: ambiente inválido (%s). Use dev, stage o prod.\n' "$CG_ENV" >&2; exit 2 ;;
esac

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

CG_COMMON_FILE="$ROOT_DIR/deploy/compose/docker-compose.common.yml"
CG_ENV_COMPOSE_FILE="$ROOT_DIR/deploy/compose/docker-compose.$CG_ENV.yml"
CG_VARS_FILE="$ROOT_DIR/deploy/compose/$CG_ENV.env"
for file in "$CG_COMMON_FILE" "$CG_ENV_COMPOSE_FILE" "$CG_VARS_FILE"; do
  [[ -f "$file" ]] || { printf 'ERROR: falta %s\n' "$file" >&2; exit 1; }
done

CG_COMPOSE=(docker compose --env-file "$CG_VARS_FILE")

add_env_file() {
  local file=$1
  [[ -f "$file" ]] || { printf 'ERROR: no existe el archivo de variables %s\n' "$file" >&2; exit 1; }
  CG_COMPOSE+=(--env-file "$file")
}

# Secrets: one file per host (HU-01) or the two local dev files.
if [[ -n "${CG_ENV_FILE:-}" ]]; then
  add_env_file "$CG_ENV_FILE"
elif [[ "$CG_ENV" == "dev" ]]; then
  add_env_file "$HOME/.circleguard/dev.env"
  if [[ -f "$HOME/.circleguard/dev-app.env" ]]; then
    add_env_file "$HOME/.circleguard/dev-app.env"
  fi
else
  add_env_file "/opt/circleguard/$CG_ENV/.env"
fi

if [[ -n "${CG_APP_ENV_FILE:-}" ]]; then
  add_env_file "$CG_APP_ENV_FILE"
fi

CG_COMPOSE+=(-f "$CG_COMMON_FILE" -f "$CG_ENV_COMPOSE_FILE")
