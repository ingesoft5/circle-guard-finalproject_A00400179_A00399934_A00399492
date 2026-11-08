#!/usr/bin/env bash
# Runs the Playwright E2E suite against an environment (HU-06).
# Usage:
#   E2E_BASE_URL=http://localhost:3000 ./deploy/e2e.sh dev
# On a Jenkins agent without browsers:
#   PLAYWRIGHT_INSTALL_BROWSERS=1 ./deploy/e2e.sh stage
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
# shellcheck source=deploy/lib.sh
source "$ROOT_DIR/deploy/lib.sh"

ENV_NAME=${1:-dev}
cg_validate_env "$ENV_NAME"
BASE_URL=${E2E_BASE_URL:-}
if [[ -z "$BASE_URL" ]]; then
  if [[ "$ENV_NAME" == "prod" ]]; then
    cg_die "E2E_BASE_URL es obligatorio para prod."
  fi
  BASE_URL="http://localhost:3000"
fi

TESTS_DIR="$ROOT_DIR/tests/e2e-playwright"
[[ -d "$TESTS_DIR" ]] || cg_die "No existe $TESTS_DIR."
command -v npm >/dev/null 2>&1 || cg_die "npm no está disponible en este agente."
command -v npx >/dev/null 2>&1 || cg_die "npx no está disponible en este agente."

cd "$TESTS_DIR"
if [[ ! -d node_modules ]]; then
  npm ci --no-audit --no-fund
fi
if [[ "${PLAYWRIGHT_INSTALL_BROWSERS:-1}" == "1" ]]; then
  npx playwright install chromium
fi

E2E_BASE_URL="$BASE_URL" CI=1 npx playwright test
cg_info "E2E OK para $ENV_NAME en $BASE_URL"
