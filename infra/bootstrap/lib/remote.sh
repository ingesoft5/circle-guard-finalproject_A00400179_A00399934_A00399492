#!/usr/bin/env bash
# Transport of the tool and environment bootstraps.
#   target aws:   commands run as root on the EC2 host over SSH (key of the host's tier).
#   target local: commands run on this machine against the local Docker engine, to validate
#                 the tool stacks for free before spending AWS credits.
# Requires common.sh and aws.sh.

cg_target_preflight() {
  if [[ "$CG_TARGET" == local ]]; then
    require_cmd docker python3 curl sha256sum
    docker info >/dev/null 2>&1 || die "Docker no está disponible en este entorno."
    info "destino local: Docker $(docker version --format '{{.Server.Version}}')"
  else
    require_cmd ssh sha256sum
    cg_aws_preflight
  fi
}

cg_stack_dir() {
  if [[ "$CG_TARGET" == local ]]; then echo "$CG_LOCAL_HOME/local/$1"; else echo "/opt/circleguard/$1"; fi
}

# cg_resolve_host <role>: selects the host for the next cg_root/cg_run_on_host calls.
# Without a running instance it returns 1 in plan mode and stops in apply mode.
cg_resolve_host() {
  local rows
  HOST_ROLE=$1
  if [[ "$CG_TARGET" == local ]]; then
    HOST_ID=local HOST_PUBLIC_IP=127.0.0.1 HOST_KEY=""
    return 0
  fi
  rows=$(cg_find_instances "$1" running)
  if [[ -z "$rows" ]]; then
    is_apply && die "No hay una instancia '$1' en ejecución. Créela o iníciela con: infra/bootstrap-servers.sh --apply --approve $1"
    info "la instancia '$1' no está en ejecución"
    return 1
  fi
  [[ $(grep -c . <<<"$rows") -eq 1 ]] || die "Hay más de una instancia con el rol '$1'."
  read -r HOST_ID _ _ HOST_PUBLIC_IP _ <<<"$rows"
  nz "$HOST_PUBLIC_IP" || die "La instancia '$1' ($HOST_ID) no tiene IPv4 pública."
  # shellcheck disable=SC2153 # PROJECT and SSH_KEY_DIR come from infra/config/aws.env
  HOST_KEY="$SSH_KEY_DIR/$PROJECT-$(cg_role_tier "$1")"
  [[ -s "$HOST_KEY" ]] || die "Falta la llave privada $HOST_KEY: ejecute infra/bootstrap-secrets.sh --apply"
}

cg_ssh() {
  ssh -i "$HOST_KEY" -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=30 \
    -o StrictHostKeyChecking=accept-new -o HostKeyAlias="$HOST_ID" \
    -o UserKnownHostsFile="$SSH_KEY_DIR/known_hosts" -o LogLevel=ERROR \
    "$SSH_USER@$HOST_PUBLIC_IP" "$@"
}

# cg_root <command>: runs a command as root on the selected host (stdin is forwarded).
cg_root() {
  if [[ "$CG_TARGET" == local ]]; then
    bash -c "$1"
  else
    cg_ssh "sudo bash -c $(printf '%q' "$1")"
  fi
}

# cg_root_script <local script> [args...]: streams a script to the selected host.
cg_root_script() {
  local script=$1
  shift
  if [[ "$CG_TARGET" == local ]]; then
    bash -s -- "$@" <"$script"
  else
    cg_ssh "sudo bash -s -- $(printf '%q ' "$@")" <"$script"
  fi
}

cg_wait_ssh() {
  local _
  [[ "$CG_TARGET" == local ]] && return 0
  for _ in $(seq 1 30); do
    if cg_ssh true 2>/dev/null; then
      info "SSH disponible en $HOST_ROLE ($HOST_ID)"
      return 0
    fi
    sleep 10
  done
  die "Sin acceso SSH a $HOST_ROLE ($(cg_mask "$HOST_PUBLIC_IP")): revise ADMIN_CIDRS y el grupo de seguridad."
}

# cg_apply_results <output>: accounts "CG_RESULT <STATUS> <text>" lines printed on the host.
cg_apply_results() {
  local line status text
  while IFS= read -r line; do
    if [[ "$line" != "CG_RESULT "* ]]; then
      [[ -n "$line" ]] && info "  $HOST_ROLE: $line"
      continue
    fi
    line=${line#CG_RESULT }
    status=${line%% *}
    text=${line#* }
    case "$status" in
      CREATED) created "$HOST_ROLE: $text" ;;
      UPDATED) updated "$HOST_ROLE: $text" ;;
      UNCHANGED) unchanged "$HOST_ROLE: $text" ;;
      PLAN) planned "$HOST_ROLE: $text" ;;
      *) info "$HOST_ROLE: $text" ;;
    esac
  done <<<"$1"
}

# cg_run_on_host <script> [args...]: runs a host script and accounts its results.
cg_run_on_host() {
  local out
  if ! out=$(cg_root_script "$@" 2>&1); then
    cg_apply_results "$out"
    die "falló ${1##*/} en $HOST_ROLE"
  fi
  cg_apply_results "$out"
}

_cg_remote_sha() { cg_root "sha256sum $(printf '%q' "$1") 2>/dev/null | cut -d' ' -f1" || true; }

# cg_sync_file <local file> <remote path> <mode>: publishes a non-secret file only if it differs.
cg_sync_file() {
  local want have q
  want=$(sha256sum "$1" | cut -d' ' -f1)
  have=$(_cg_remote_sha "$2")
  if [[ "$want" == "$have" ]]; then
    unchanged "$HOST_ROLE: $2"
    return 0
  fi
  if ! is_apply; then
    planned "$HOST_ROLE: publicar $2"
    return 0
  fi
  q=$(printf '%q' "$2")
  cg_root "install -d -m 0755 \"\$(dirname $q)\" && cat > $q.tmp && chmod $3 $q.tmp && mv -f $q.tmp $q" <"$1"
  CG_FILES_CHANGED=true
  if [[ -z "$have" ]]; then created "$HOST_ROLE: $2"; else updated "$HOST_ROLE: $2"; fi
}

# cg_sync_secret <remote path>: content from stdin, stored with mode 0600 only if it differs.
# The content is never displayed: only "written" or "unchanged" is reported.
cg_sync_secret() {
  local content want have q
  content=$(cat)
  want=$(printf '%s\n' "$content" | sha256sum | cut -d' ' -f1)
  have=$(_cg_remote_sha "$1")
  if [[ "$want" == "$have" ]]; then
    unchanged "$HOST_ROLE: $1 (0600, contenido no mostrado)"
    return 0
  fi
  if ! is_apply; then
    planned "$HOST_ROLE: escribir $1 (0600)"
    return 0
  fi
  q=$(printf '%q' "$1")
  printf '%s\n' "$content" | cg_root "umask 077 && install -d -m 0755 \"\$(dirname $q)\" && cat > $q.tmp && mv -f $q.tmp $q"
  if [[ -z "$have" ]]; then created "$HOST_ROLE: $1 (0600, contenido no mostrado)"; else updated "$HOST_ROLE: $1 (0600, contenido no mostrado)"; fi
}

# cg_tool_bootstrap <tool>: shared flow of bootstrap-jenkins/sonarqube/nexus.sh.
# The caller defines TOOL_FILES (relative to infra/bootstrap/<tool>/), TOOL_ENV (non-secret
# KEY=VALUE lines) and TOOL_SECRETS (names in the tools/<tool> scope). CG_TOOL_ENV_HOOK may
# name a function that fills TOOL_ENV once the host (and its public IP) is known.
cg_tool_bootstrap() {
  local tool=$1 src="$INFRA_DIR/bootstrap/$1" project="circleguard-$1" dir f env_content before after
  cg_target_preflight
  if ! cg_resolve_host "$tool"; then
    planned "$tool: preparar el host, publicar el stack y configurarlo cuando la instancia esté en ejecución"
    return 0
  fi
  if [[ -n "${CG_TOOL_ENV_HOOK:-}" ]]; then "$CG_TOOL_ENV_HOOK"; fi
  if [[ "$CG_TARGET" == aws ]]; then
    cg_wait_ssh
    cg_run_on_host "$INFRA_DIR/bootstrap/host/setup-docker.sh" "$tool" "$CG_MODE"
  fi

  dir=$(cg_stack_dir "$tool")
  CG_FILES_CHANGED=false
  for f in "${TOOL_FILES[@]}"; do cg_sync_file "$src/$f" "$dir/$f" 0644; done
  env_content=$({
    printf '%s\n' "${TOOL_ENV[@]}"
    cg_render_env "tools/$tool" "${TOOL_SECRETS[@]}"
  } | sort)
  cg_sync_secret "$dir/.env" <<<"$env_content"
  env_content=""

  before=$(cg_root "docker ps -a --filter label=com.docker.compose.project=$project --format '{{.Names}}={{.ID}}' | sort")
  if is_apply; then
    # Images are rebuilt only when the build context changed: every BuildKit build gets a new
    # digest (provenance timestamp), so an unconditional --build would recreate containers.
    local build=""
    [[ "$CG_FILES_CHANGED" == true ]] && build=--build
    info "$tool: docker compose up -d ${build:-(sin reconstruir: el contexto no cambió)}"
    cg_root "cd $(printf '%q' "$dir") && docker compose up -d $build --remove-orphans --quiet-pull" >&2
    after=$(cg_root "docker ps -a --filter label=com.docker.compose.project=$project --format '{{.Names}}={{.ID}}' | sort")
    if [[ "$before" == "$after" ]]; then
      unchanged "$tool: contenedores sin cambios ($project)"
    elif [[ -z "$before" ]]; then
      created "$tool: stack $project desplegado con Docker Compose"
    else
      updated "$tool: stack $project actualizado con Docker Compose"
    fi
  elif [[ -z "$before" ]]; then
    planned "$tool: desplegar el stack $project con Docker Compose"
    planned "$tool: configurar la herramienta por API una vez desplegada"
    return 0
  fi

  cg_run_on_host "$src/configure.sh" "$dir" "$CG_MODE"
}
