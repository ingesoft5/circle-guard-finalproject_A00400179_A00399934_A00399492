#!/usr/bin/env bash
# Starts a CircleGuard environment and waits for every healthcheck (HU-02).
# Usage:
#   ./deploy/compose-up.sh dev
#   CG_ENV_FILE=/opt/circleguard/stage/.env ./deploy/compose-up.sh stage
# Local dev defaults to ~/.circleguard/dev.env + dev-app.env (HU-01).
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_NAME=${1:-}
[[ -n "$ENV_NAME" ]] || { printf 'Uso: %s <dev|stage|prod>\n' "$0" >&2; exit 2; }

# shellcheck source=deploy/compose-env.sh
source "$ROOT_DIR/deploy/compose-env.sh" "$ENV_NAME"
# shellcheck source=deploy/lib.sh
source "$ROOT_DIR/deploy/lib.sh"
cg_require_docker

# The image tag comes from the shell or from the environment file. 'latest' is never allowed.
TAG=${IMAGE_TAG:-$(sed -n 's/^IMAGE_TAG=//p' "$CG_VARS_FILE" | tail -n 1)}
[[ "$TAG" != "latest" ]] || cg_die "El tag 'latest' está prohibido. Use una versión semántica (1.0.0)."
if [[ -n "$TAG" ]]; then
  cg_validate_semver "$TAG"
fi

# PostgreSQL creates only the default database. The service databases are created explicitly
# because a bind mount of init-db.sql from the Jenkins workspace is not visible to the DinD daemon.
"${CG_COMPOSE[@]}" up -d --wait postgres
"${CG_COMPOSE[@]}" exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d postgres' < "$ROOT_DIR/init-db.sql"
"${CG_COMPOSE[@]}" up -d --wait --wait-timeout "${CG_WAIT_TIMEOUT:-600}"
"${CG_COMPOSE[@]}" ps
