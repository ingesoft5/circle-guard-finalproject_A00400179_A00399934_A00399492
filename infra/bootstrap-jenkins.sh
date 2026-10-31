#!/usr/bin/env bash
# HU-01 · Jenkins server: prepares the host (Docker Engine + Compose), publishes the Compose
# stack and the JCasC configuration, writes its .env from the secret manager and verifies that
# Jenkins started configured (no setup wizard, managed admin, no anonymous access).
# Jenkins only listens on 127.0.0.1 of its host: administrators use infra/tunnel.sh jenkins.
# Idempotent. It does not create AWS resources: the instance must already exist.

# shellcheck source=bootstrap/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/aws.sh
source "$INFRA_DIR/bootstrap/lib/aws.sh"
# shellcheck source=bootstrap/lib/remote.sh
source "$INFRA_DIR/bootstrap/lib/remote.sh"

usage() {
  cat <<'EOF'
Uso: infra/bootstrap-jenkins.sh [--plan | --apply] [--target aws|local]
  --target aws    (por defecto) instancia EC2 "jenkins" en ejecución, por SSH.
  --target local  Docker Desktop de esta máquina, en 127.0.0.1 (validación gratuita).
EOF
}

cg_parse_flags "$@"
cg_load_config
cg_start_log bootstrap-jenkins

if [[ "$CG_TARGET" == local ]]; then RESTART=no; else RESTART=unless-stopped; fi
# TOOL_* are read by cg_tool_bootstrap (bootstrap/lib/remote.sh). The URL is the one seen
# through the SSH tunnel, so it does not change when the instance gets a new public IP.
# shellcheck disable=SC2034
TOOL_FILES=(docker-compose.yml Dockerfile plugins.txt casc/jenkins.yaml)
# shellcheck disable=SC2034
TOOL_SECRETS=(JENKINS_ADMIN_PASSWORD)
# shellcheck disable=SC2034
TOOL_ENV=(
  "BIND_ADDRESS=127.0.0.1"
  "RESTART_POLICY=$RESTART"
  "JENKINS_HTTP_PORT=$JENKINS_HTTP_PORT"
  "JENKINS_ADMIN_USER=admin"
  "CG_JENKINS_URL=http://localhost:${JENKINS_HTTP_PORT}/"
)

cg_tool_bootstrap jenkins
cg_summary bootstrap-jenkins
