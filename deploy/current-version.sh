#!/usr/bin/env bash
# Prints the version currently recorded for an environment (HU-06).
# Usage: ./deploy/current-version.sh <dev|stage|prod>
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
# shellcheck source=deploy/lib.sh
source "$ROOT_DIR/deploy/lib.sh"

ENV_NAME=${1:-}
cg_validate_env "$ENV_NAME"
cg_current_version "$ENV_NAME"
