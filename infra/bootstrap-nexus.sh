#!/usr/bin/env bash
# HU-01 · Nexus Repository server: prepares the host (Docker Engine + Compose), publishes the
# Nexus stack, writes its .env from the secret manager and configures Nexus through its REST
# API: managed admin password, anonymous access off, Docker Bearer Token realm and the Docker
# hosted repository "circleguard-docker". Idempotent. It does not create AWS resources.

# shellcheck source=bootstrap/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/aws.sh
source "$INFRA_DIR/bootstrap/lib/aws.sh"
# shellcheck source=bootstrap/lib/remote.sh
source "$INFRA_DIR/bootstrap/lib/remote.sh"

usage() {
  cat <<'EOF'
Uso: infra/bootstrap-nexus.sh [--plan | --apply] [--target aws|local]
  --target aws    (por defecto) instancia EC2 "nexus" en ejecución, por SSH.
  --target local  Docker Desktop de esta máquina, en 127.0.0.1 (validación gratuita).
EOF
}

cg_parse_flags "$@"
cg_load_config
cg_start_log bootstrap-nexus

if [[ "$CG_TARGET" == local ]]; then
  BIND=127.0.0.1 RESTART=no DOCKER_HOST_PORT=$LOCAL_NEXUS_DOCKER_HOST_PORT
else
  BIND=0.0.0.0 RESTART=unless-stopped DOCKER_HOST_PORT=$NEXUS_DOCKER_PORT
fi
# TOOL_* are read by cg_tool_bootstrap (bootstrap/lib/remote.sh).
# shellcheck disable=SC2034
TOOL_FILES=(docker-compose.yml repositories/circleguard-docker.json)
# shellcheck disable=SC2034
TOOL_SECRETS=(NEXUS_ADMIN_PASSWORD)
# shellcheck disable=SC2034
TOOL_ENV=(
  "BIND_ADDRESS=$BIND"
  "RESTART_POLICY=$RESTART"
  "NEXUS_HTTP_PORT=$NEXUS_HTTP_PORT"
  "NEXUS_DOCKER_PORT=$NEXUS_DOCKER_PORT"
  "NEXUS_DOCKER_HOST_PORT=$DOCKER_HOST_PORT"
  "NEXUS_ACCEPT_EULA=$NEXUS_ACCEPT_EULA"
)

cg_tool_bootstrap nexus
cg_summary bootstrap-nexus
