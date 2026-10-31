#!/usr/bin/env bash
# HU-01 · SonarQube server: prepares the host (Docker Engine + Compose, vm.max_map_count),
# publishes the SonarQube + PostgreSQL stack, writes its .env from the secret manager and,
# through SonarQube's Web API, replaces the factory admin password and keeps anonymous access
# disabled. Idempotent. It does not create AWS resources: the instance must already exist.

# shellcheck source=bootstrap/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/aws.sh
source "$INFRA_DIR/bootstrap/lib/aws.sh"
# shellcheck source=bootstrap/lib/remote.sh
source "$INFRA_DIR/bootstrap/lib/remote.sh"

usage() {
  cat <<'EOF'
Uso: infra/bootstrap-sonarqube.sh [--plan | --apply] [--target aws|local]
  --target aws    (por defecto) instancia EC2 "sonarqube" en ejecución, por SSH.
  --target local  Docker Desktop de esta máquina, en 127.0.0.1 (validación gratuita).
EOF
}

cg_parse_flags "$@"
cg_load_config
cg_start_log bootstrap-sonarqube

if [[ "$CG_TARGET" == local ]]; then BIND=127.0.0.1 RESTART=no; else BIND=0.0.0.0 RESTART=unless-stopped; fi
# TOOL_* are read by cg_tool_bootstrap (bootstrap/lib/remote.sh).
# shellcheck disable=SC2034
TOOL_FILES=(docker-compose.yml)
# shellcheck disable=SC2034
TOOL_SECRETS=(SONAR_ADMIN_PASSWORD SONAR_DB_PASSWORD)
# shellcheck disable=SC2034
TOOL_ENV=(
  "BIND_ADDRESS=$BIND"
  "RESTART_POLICY=$RESTART"
  "SONARQUBE_HTTP_PORT=$SONARQUBE_HTTP_PORT"
)

cg_tool_bootstrap sonarqube
cg_summary bootstrap-sonarqube
