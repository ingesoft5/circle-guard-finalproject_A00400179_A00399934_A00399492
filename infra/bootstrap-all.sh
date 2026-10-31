#!/usr/bin/env bash
# HU-01 · Single command that builds (or converges) the whole platform from scratch:
#   network -> secrets -> servers -> jenkins -> sonarqube -> nexus -> dev/stage/prod -> verify
# Every step is idempotent: a second run over converged infrastructure reports
# created=0 updated=0. Billable servers are only created or started for the roles listed in
# --approve. Without --apply nothing is changed.

# shellcheck source=bootstrap/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/aws.sh
source "$INFRA_DIR/bootstrap/lib/aws.sh"

usage() {
  cat <<'EOF'
Uso: infra/bootstrap-all.sh [--plan | --apply --approve <roles>]
  --plan   (por defecto) recorre todos los pasos sin cambiar nada y muestra el costo estimado.
  --apply --approve all                      reconstruye toda la plataforma (FACTURABLE).
  --apply --approve jenkins,sonarqube,...    solo crea o inicia los servidores aprobados; los
                                             pasos de los demás roles se omiten.
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

# running_or_skip <role>: in apply mode, steps of servers that are not running are skipped.
running_or_skip() {
  if is_apply && [[ -z "$(cg_find_instances "$1" running)" ]]; then
    warn "se omite la configuración de $1: su instancia no está en ejecución (no fue aprobada o no existe)"
    return 1
  fi
}

cg_aws_preflight
step bootstrap-network.sh "--$CG_MODE"
step bootstrap-secrets.sh "--$CG_MODE"
step bootstrap-servers.sh "${FLAGS[@]}"
for tool in jenkins sonarqube nexus; do
  if running_or_skip "$tool"; then step "bootstrap-$tool.sh" "--$CG_MODE"; fi
done
for env_name in "${CG_ENVS[@]}"; do
  if running_or_skip "env-$env_name"; then step bootstrap-env.sh "$env_name" "--$CG_MODE"; fi
done
if is_apply; then step verify-infra.sh --health; fi

read -r created updated unchanged planned < <(awk '{c += $2; u += $3; n += $4; p += $5} END {print c+0, u+0, n+0, p+0}' "$CG_COUNTERS_FILE")
log SUMMARY "bootstrap-all created=$created updated=$updated unchanged=$unchanged planned=$planned duración=$(($(date +%s) - STARTED))s"
if is_apply && ((created == 0 && updated == 0)); then
  info "la infraestructura ya estaba en el estado deseado: ejecución idempotente sin cambios"
fi
