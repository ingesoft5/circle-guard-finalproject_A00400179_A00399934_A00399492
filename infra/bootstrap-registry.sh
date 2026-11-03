#!/usr/bin/env bash
# HU-01 · Docker registry on the nexus server: CNCF Distribution 3.0 (Apache 2.0, no EULA), used
# while the Nexus Community Edition EULA is pending (REGISTRY_BACKEND=distribution; trade-offs in
# docs/arquitectura/registro-artefactos.md). Prepares the host, publishes the stack, writes its
# .env from the secret manager, generates the TLS certificate and the htpasswd user on the host
# (prepare.sh) and checks that the registry requires authentication (configure.sh).
# It listens on the registry port (NEXUS_DOCKER_PORT), which the security groups open only to ci
# and the environments. With REGISTRY_BACKEND=nexus it retires the stack instead (the volume with
# the images is kept), so that the Nexus connector can take the port.
# Idempotent. It does not create AWS resources: the instance must already exist.

# shellcheck source=bootstrap/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/aws.sh
source "$INFRA_DIR/bootstrap/lib/aws.sh"
# shellcheck source=bootstrap/lib/remote.sh
source "$INFRA_DIR/bootstrap/lib/remote.sh"

usage() {
  cat <<'EOF'
Uso: infra/bootstrap-registry.sh [--plan | --apply] [--target aws|local]
  --target aws    (por defecto) instancia EC2 "nexus" en ejecución, por SSH.
  --target local  Docker Desktop de esta máquina, en 127.0.0.1 (validación gratuita).
EOF
}

# retire: with REGISTRY_BACKEND=nexus, stops and removes the Distribution containers (never its
# volume) so that Nexus can publish the registry port.
retire() {
  local dir
  cg_target_preflight
  if ! cg_resolve_host "$(cg_tool_host registry)"; then
    info "registro: REGISTRY_BACKEND=nexus; nada que retirar mientras el servidor no esté en ejecución"
    return 0
  fi
  cg_wait_ssh
  dir=$(cg_stack_dir registry)
  if [[ -z "$(cg_root "docker ps -aq --filter label=com.docker.compose.project=circleguard-registry")" ]]; then
    unchanged "registro: REGISTRY_BACKEND=nexus; el stack de Distribution no está desplegado"
  elif is_apply; then
    cg_root "cd $(printf '%q' "$dir") && docker compose down --remove-orphans" >&2
    updated "registro: stack de Distribution retirado (REGISTRY_BACKEND=nexus); el volumen con las imágenes se conserva"
  else
    planned "registro: retirar el stack de Distribution (REGISTRY_BACKEND=nexus) conservando su volumen"
  fi
}

cg_parse_flags "$@"
cg_load_config
cg_start_log bootstrap-registry

if [[ "$REGISTRY_BACKEND" != distribution ]]; then
  retire
  cg_summary bootstrap-registry
  exit 0
fi

if [[ "$CG_TARGET" == local ]]; then
  BIND=127.0.0.1 RESTART=no PORT=$LOCAL_NEXUS_DOCKER_HOST_PORT
else
  BIND=0.0.0.0 RESTART=unless-stopped PORT=$NEXUS_DOCKER_PORT
fi
# TOOL_* are read by cg_tool_bootstrap (bootstrap/lib/remote.sh).
# shellcheck disable=SC2034
TOOL_FILES=(docker-compose.yml config.yml)
# shellcheck disable=SC2034
TOOL_SECRETS=(REGISTRY_CI_PASSWORD)
# shellcheck disable=SC2034
TOOL_ENV=(
  "BIND_ADDRESS=$BIND"
  "RESTART_POLICY=$RESTART"
  "REGISTRY_HOST_PORT=$PORT"
  "REGISTRY_CI_USER=ci"
)

cg_tool_bootstrap registry
cg_summary bootstrap-registry
