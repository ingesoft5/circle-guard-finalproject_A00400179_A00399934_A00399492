#!/usr/bin/env bash
# HU-01 · Single command that builds (or converges) the whole platform from scratch:
#   network -> secrets -> servers -> jenkins + sonarqube (ci) -> nexus + registry (nexus server)
#   -> environment hosts (only those in ENV_SERVERS that are running) -> verify
# dev, stage and prod are isolated by network (subnet + security group); they only get servers
# when the team lists them in ENV_SERVERS. Every step is idempotent: a second run over converged
# infrastructure reports created=0 updated=0. Billable servers are only created or started for
# the roles listed in --approve. Without --apply nothing is changed.

# shellcheck source=bootstrap/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/aws.sh
source "$INFRA_DIR/bootstrap/lib/aws.sh"

usage() {
  cat <<'EOF'
Uso: infra/bootstrap-all.sh [--plan | --apply --approve <roles>]
  --plan   (por defecto) recorre todos los pasos sin cambiar nada y muestra el costo estimado.
  --apply --approve all        reconstruye toda la plataforma: servidores ci y nexus, y los
                               ambientes de ENV_SERVERS si los hay (FACTURABLE).
  --apply --approve ci         solo crea o inicia los servidores aprobados; los pasos de los
                               demás se omiten. Roles: ci, nexus, env-<ambiente> (de ENV_SERVERS).
EOF
}

cg_parse_flags "$@"
[[ "$CG_TARGET" == aws ]] || die "bootstrap-all.sh solo aplica a AWS. Para validar en local use bootstrap-<herramienta>.sh --target local."
cg_load_config
cg_start_log bootstrap-all
export CG_COUNTERS_FILE
CG_COUNTERS_FILE=$(mktemp)
trap 'rm -f "$CG_COUNTERS_FILE"' EXIT

FLAGS=(--"$CG_MODE")
[[ -n "$CG_APPROVED" ]] && FLAGS+=(--approve "$CG_APPROVED")
STARTED=$(date +%s)

step() { # step <script> [args]
  info "==== ${1##*/} ${*:2}"
  bash "$INFRA_DIR/$1" "${@:2}"
}

# running_or_skip <role>: steps of servers that are not running are skipped (in plan mode too:
# there is nothing to configure yet, and configuring needs the operator role).
running_or_skip() {
  [[ -n "$(cg_find_instances "$1" running)" ]] && return 0
  if is_apply; then
    warn "se omite la configuración de $1: su instancia no está en ejecución (no fue aprobada o no existe)"
  else
    info "configuración de $1: se planificará cuando su instancia esté en ejecución"
  fi
  return 1
}

# running_roles: comma separated roles whose instance is running (what verify-infra can check).
running_roles() {
  local role list=()
  for role in "${CG_ROLES[@]}"; do
    if [[ -n "$(cg_find_instances "$role" running)" ]]; then list+=("$role"); fi
  done
  (IFS=,; echo "${list[*]}")
}

cg_aws_preflight
step bootstrap-network.sh "--$CG_MODE"
step bootstrap-secrets.sh "--$CG_MODE"
step bootstrap-servers.sh "${FLAGS[@]}"
# The tools of the nexus server go in the order that frees the registry port before taking it.
read -ra NEXUS_TOOLS <<<"$(cg_registry_tools)"
for tool in jenkins sonarqube "${NEXUS_TOOLS[@]}"; do
  if running_or_skip "$(cg_tool_host "$tool")"; then step "bootstrap-$tool.sh" "--$CG_MODE"; fi
done
for env_name in "${CG_ENVS[@]}"; do
  if [[ -n "$(cg_find_instances "env-$env_name" running)" ]]; then
    step bootstrap-env.sh "$env_name" "--$CG_MODE"
  elif [[ " ${CG_ROLES[*]} " == *" env-$env_name "* ]]; then
    info "ambiente $env_name: su servidor (ENV_SERVERS) no está en ejecución; se preparará cuando lo esté"
  else
    info "ambiente $env_name: aislado por red (subred y grupo de seguridad propios), sin servidor (ENV_SERVERS)"
  fi
done
if is_apply; then
  # Sessions bring up only the approved servers: verify those that are running.
  ROLES_UP=$(running_roles)
  if [[ -n "$ROLES_UP" ]]; then step verify-infra.sh --health "--roles=$ROLES_UP"; else warn "no hay servidores en ejecución: se omite la verificación"; fi
fi

read -r created updated unchanged planned < <(awk '{c += $2; u += $3; n += $4; p += $5} END {print c+0, u+0, n+0, p+0}' "$CG_COUNTERS_FILE")
log SUMMARY "bootstrap-all created=$created updated=$updated unchanged=$unchanged planned=$planned duración=$(($(date +%s) - STARTED))s"
if is_apply && ((created == 0 && updated == 0)); then
  info "la infraestructura ya estaba en el estado deseado: ejecución idempotente sin cambios"
fi
