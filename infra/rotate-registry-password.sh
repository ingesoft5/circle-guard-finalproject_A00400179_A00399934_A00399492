#!/usr/bin/env bash
# HU-01 · Rotation of the password of the registry user "ci" (CNCF Distribution), consumed by
# Jenkins. With --apply:
#   1. keeps the current value in memory (never printed) to prove later that it stops working;
#   2. writes a new random value to the secret manager (SSM: a new version of the parameter;
#      --target local: the file under ~/.circleguard/secrets);
#   3. bootstrap-registry.sh --apply: the htpasswd user is rewritten and the registry restarted;
#   4. bootstrap-jenkins.sh --apply when Jenkins runs: its .env changes and the container is
#      recreated (jenkins_home is a volume: no data is lost); otherwise its next bootstrap does it;
#   5. checks: the new value authenticates (HTTP 200), the old one is rejected (HTTP 401) and, with
#      Jenkins running, verify-infra.sh --registry publishes and pulls from the Jenkins container.
# Recovery: if step 3 fails, the previous value is written back and the registry re-converged.
# Requires the registry server running (nexus). Values only travel through pipes and variables.

# shellcheck source=bootstrap/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/aws.sh
source "$INFRA_DIR/bootstrap/lib/aws.sh"
# shellcheck source=bootstrap/lib/remote.sh
source "$INFRA_DIR/bootstrap/lib/remote.sh"

usage() {
  cat <<'EOF'
Uso: infra/rotate-registry-password.sh [--plan | --apply] [--target aws|local]
  --plan    (por defecto) muestra los pasos sin cambiar nada.
  --apply   rota la contraseña del usuario ci del registro y actualiza el registro y Jenkins.
            Pide escribir 'ROTAR REGISTRO' (o exportar CG_CONFIRM con esa frase).
EOF
}

SCOPE=tools/registry
NAME=REGISTRY_CI_PASSWORD

# secret_replace: new value from stdin; never printed.
secret_replace() {
  if [[ "$CG_TARGET" == local ]]; then
    local file="$CG_LOCAL_HOME/secrets/$SCOPE/$NAME"
    (umask 077 && cat >"$file.new" && mv -f "$file.new" "$file")
    return
  fi
  (
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    python3 -c '
import json, sys
json.dump({"Name": sys.argv[1], "Value": sys.stdin.read(), "Type": "SecureString", "Overwrite": True}, open(sys.argv[2], "w"))
' "$(cg_secret_param "$SCOPE" "$NAME")" "$tmp/request.json"
    aws_ ssm put-parameter --cli-input-json "file://$tmp/request.json" >/dev/null
  )
}

# registry_code: HTTP code of the registry for the user ci with the password read from stdin.
registry_code() {
  local port=$NEXUS_DOCKER_PORT
  [[ "$CG_TARGET" == local ]] && port=$LOCAL_NEXUS_DOCKER_HOST_PORT
  { printf 'user = "ci:'; cat; printf '"\n'; } |
    cg_root "curl -sk -o /dev/null -w '%{http_code}' --max-time 10 -K - https://127.0.0.1:$port/v2/" || true
}

jenkins_running() {
  if [[ "$CG_TARGET" == local ]]; then
    [[ "$(docker inspect -f '{{.State.Running}}' cg-jenkins 2>/dev/null)" == true &&
      -f "$(cg_stack_dir jenkins)/.env" ]]
  else
    [[ -n "$(cg_find_instances ci running)" ]]
  fi
}

cg_parse_flags "$@"
cg_load_config
[[ "$REGISTRY_BACKEND" == distribution ]] || die "La rotación aplica al registro CNCF Distribution (REGISTRY_BACKEND=distribution)."
cg_start_log rotate-registry-password
cg_target_preflight
TARGET=(--target "$CG_TARGET")
if ! cg_resolve_host "$(cg_tool_host registry)"; then
  planned "rotar la contraseña del usuario ci del registro cuando el servidor $(cg_tool_host registry) esté en ejecución"
  cg_summary rotate-registry-password
  exit 0
fi
if ! is_apply; then
  planned "rotar $(cg_secret_param "$SCOPE" "$NAME"): nueva versión en el gestor de secretos"
  planned "bootstrap-registry.sh --apply: reescribir el usuario ci y reiniciar el registro"
  planned "bootstrap-jenkins.sh --apply (si Jenkins está en ejecución): recrear su contenedor con la nueva contraseña"
  planned "comprobar que la contraseña nueva autentica (200) y la anterior no (401)"
  cg_summary rotate-registry-password
  exit 0
fi
confirm "ROTAR REGISTRO" "Se cambiará la contraseña del usuario ci del registro y se reiniciarán el registro y Jenkins."
cg_wait_ssh

old=$(cg_secret_get "$SCOPE" "$NAME")
cg_generate password | secret_replace
updated "secreto $(cg_secret_param "$SCOPE" "$NAME") rotado (valor no mostrado)"

if ! bash "$INFRA_DIR/bootstrap-registry.sh" --apply "${TARGET[@]}"; then
  warn "falló la actualización del registro: se restaura la contraseña anterior"
  printf '%s' "$old" | secret_replace
  old=""
  bash "$INFRA_DIR/bootstrap-registry.sh" --apply "${TARGET[@]}" || warn "el registro no convergió con la contraseña anterior: revíselo antes de continuar"
  die "rotación revertida: la contraseña anterior vuelve a estar vigente"
fi

if jenkins_running; then
  bash "$INFRA_DIR/bootstrap-jenkins.sh" --apply "${TARGET[@]}" || die "falló la actualización de Jenkins: ejecute de nuevo bash infra/bootstrap-jenkins.sh --apply"
  JENKINS_UPDATED=true
else
  warn "Jenkins no está en ejecución: recibirá la contraseña nueva en su próxima ejecución de bootstrap-jenkins.sh"
  JENKINS_UPDATED=false
fi

cg_resolve_host "$(cg_tool_host registry)" >/dev/null
new_code=$(cg_secret_get "$SCOPE" "$NAME" | registry_code)
old_code=$(printf '%s' "$old" | registry_code)
old=""
[[ "$new_code" == 200 ]] || die "la contraseña nueva no autentica en el registro (HTTP $new_code)"
unchanged "la contraseña nueva autentica en el registro (HTTP 200)"
[[ "$old_code" == 401 ]] || die "la contraseña anterior todavía responde HTTP $old_code"
unchanged "la contraseña anterior ya no autentica (HTTP 401)"
if $JENKINS_UPDATED; then
  roles=()
  [[ "$CG_TARGET" == aws ]] && roles=("--roles=ci,nexus")
  bash "$INFRA_DIR/verify-infra.sh" --registry "${roles[@]}" "${TARGET[@]}" || die "verify-infra.sh --registry falló tras la rotación"
fi
cg_summary rotate-registry-password
