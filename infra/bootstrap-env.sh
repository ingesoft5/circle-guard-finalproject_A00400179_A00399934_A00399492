#!/usr/bin/env bash
# HU-01 · Environment host (dev, stage or prod): prepares the host (Docker Engine + Compose)
# and writes /opt/circleguard/<env>/.env (mode 0600) with the credentials of THAT environment
# only. Deploying CircleGuard on the host belongs to E1.3/E1.5. Idempotent. It does not create
# AWS resources: the instance must already exist.

# shellcheck source=bootstrap/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/aws.sh
source "$INFRA_DIR/bootstrap/lib/aws.sh"
# shellcheck source=bootstrap/lib/remote.sh
source "$INFRA_DIR/bootstrap/lib/remote.sh"

usage() {
  cat <<'EOF'
Uso: infra/bootstrap-env.sh <dev|stage|prod> [--plan | --apply]
  Prepara el host del ambiente indicado (instancia EC2 env-<ambiente> en ejecución).
EOF
}

cg_parse_flags "$@"
ENV_NAME=${CG_ARGS[0]:-}
cg_validate_env "$ENV_NAME"
[[ "$CG_TARGET" == aws ]] || die "Los ambientes dev, stage y prod solo existen en AWS: --target local no aplica."
cg_load_config
cg_start_log "bootstrap-env-$ENV_NAME"
cg_target_preflight

ROLE="env-$ENV_NAME"
if ! cg_resolve_host "$ROLE"; then
  planned "$ROLE: preparar el host y sus credenciales cuando la instancia esté en ejecución"
  cg_summary "bootstrap-env-$ENV_NAME"
  exit 0
fi
cg_wait_ssh
cg_run_on_host "$INFRA_DIR/bootstrap/host/setup-docker.sh" "$ROLE" "$CG_MODE"

mapfile -t NAMES < <(cg_catalog | awk -v env="$ENV_NAME" '$1 == env { print $2 }')
ENV_CONTENT=$({
  echo "ENV_NAME=$ENV_NAME"
  cg_render_env "$ENV_NAME" "${NAMES[@]}"
} | sort)
cg_sync_secret "/opt/circleguard/$ENV_NAME/.env" <<<"$ENV_CONTENT"
ENV_CONTENT=""

# Isolation of credentials: the host must not hold directories of other environments.
OTHERS=$(cg_root "ls -1 /opt/circleguard 2>/dev/null" | grep -v -x "$ENV_NAME" || true)
if [[ -n "$OTHERS" ]]; then
  die "El host de $ENV_NAME contiene datos de otros ambientes en /opt/circleguard: $(tr '\n' ' ' <<<"$OTHERS")"
fi
unchanged "$ROLE: el host solo contiene las credenciales de $ENV_NAME (${#NAMES[@]} variables)"
cg_summary "bootstrap-env-$ENV_NAME"
