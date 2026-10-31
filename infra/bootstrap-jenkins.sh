#!/usr/bin/env bash
# HU-01 · Jenkins server: prepares the host (Docker Engine + Compose), publishes the Compose
# stack and the JCasC configuration, writes its .env from the secret manager and verifies that
# Jenkins started configured (no setup wizard, managed admin, no anonymous access).
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

if [[ "$CG_TARGET" == local ]]; then
  JENKINS_URL_VALUE="http://localhost:${JENKINS_HTTP_PORT}/"
  BIND=127.0.0.1 RESTART=no
else
  BIND=0.0.0.0 RESTART=unless-stopped
fi

# TOOL_* and CG_TOOL_ENV_HOOK are read by cg_tool_bootstrap (bootstrap/lib/remote.sh).
# shellcheck disable=SC2034
TOOL_FILES=(docker-compose.yml Dockerfile plugins.txt casc/jenkins.yaml)
# shellcheck disable=SC2034
TOOL_SECRETS=(JENKINS_ADMIN_PASSWORD)
# The public URL is only known once the host is resolved: cg_tool_bootstrap reads TOOL_ENV
# after cg_resolve_host, so it is filled from a hook.
jenkins_env() {
  # shellcheck disable=SC2034
  TOOL_ENV=(
    "BIND_ADDRESS=$BIND"
    "RESTART_POLICY=$RESTART"
    "JENKINS_HTTP_PORT=$JENKINS_HTTP_PORT"
    "JENKINS_ADMIN_USER=admin"
    "CG_JENKINS_URL=${JENKINS_URL_VALUE:-http://${HOST_PUBLIC_IP}:${JENKINS_HTTP_PORT}/}"
  )
}
# shellcheck disable=SC2034
CG_TOOL_ENV_HOOK=jenkins_env

cg_tool_bootstrap jenkins
cg_summary bootstrap-jenkins
