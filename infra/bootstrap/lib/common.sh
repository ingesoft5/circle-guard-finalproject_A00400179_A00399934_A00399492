#!/usr/bin/env bash
# Shared helpers of the HU-01 infrastructure scripts (infra/*.sh). Source it; do not run it.
#
# Conventions
#   * Every change is reported as CREATED or UPDATED, a verified state as UNCHANGED and what
#     --plan would do as PLAN. A second run over converged infrastructure reports
#     created=0 updated=0.
#   * --plan is the default: nothing is created or modified. --apply changes things; billable
#     servers additionally need --approve <role>.
#   * Secret values are never printed nor passed as command-line arguments: only names,
#     versions and hashes appear in the output and in infra/logs/.

set -Eeuo pipefail
shopt -s lastpipe

if ((BASH_VERSINFO[0] < 4)); then
  echo "Se requiere Bash 4 o superior (use WSL Ubuntu)." >&2
  exit 1
fi

CG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "$CG_LIB_DIR/../.." && pwd)"
REPO_DIR="$(cd "$INFRA_DIR/.." && pwd)"
export INFRA_DIR REPO_DIR
export AWS_PAGER="" MSYS_NO_PATHCONV=1

CG_CREATED=0
CG_UPDATED=0
CG_UNCHANGED=0
CG_PLANNED=0
CG_MODE=plan
CG_TARGET=aws
CG_APPROVED=""
CG_ASSUME_YES=false
CG_ARGS=()
CG_ENVS=(dev stage prod)
CG_LOCAL_HOME="${CG_LOCAL_HOME:-$HOME/.circleguard}"

log()       { printf '%s %-9s %s\n' "$(date -u +%H:%M:%S)" "$1" "${*:2}" >&2; }
info()      { log INFO "$@"; }
warn()      { log WARN "$@"; }
die()       { log ERROR "$@"; exit 1; }
created()   { CG_CREATED=$((CG_CREATED + 1)); log CREATED "$@"; }
updated()   { CG_UPDATED=$((CG_UPDATED + 1)); log UPDATED "$@"; }
unchanged() { CG_UNCHANGED=$((CG_UNCHANGED + 1)); log UNCHANGED "$@"; }
planned()   { CG_PLANNED=$((CG_PLANNED + 1)); log PLAN "$@"; }

trap 'log ERROR "falló ${BASH_SOURCE[0]##*/}:${LINENO}"' ERR

# cg_parse_flags "$@": common flags; anything else is left in CG_ARGS. Callers define usage().
cg_parse_flags() {
  while (($#)); do
    # shellcheck disable=SC2034 # CG_ASSUME_YES is read by teardown.sh
    case "$1" in
      --plan) CG_MODE=plan ;;
      --apply) CG_MODE=apply ;;
      --approve) (($# >= 2)) || die "--approve requiere una lista de roles"; CG_APPROVED=$2; shift ;;
      --approve=*) CG_APPROVED=${1#*=} ;;
      --target) (($# >= 2)) || die "--target requiere aws o local"; CG_TARGET=$2; shift ;;
      --target=*) CG_TARGET=${1#*=} ;;
      --yes) CG_ASSUME_YES=true ;;
      -h | --help) usage; exit 0 ;;
      *) CG_ARGS+=("$1") ;;
    esac
    shift
  done
  case "$CG_TARGET" in aws | local) ;; *) die "--target inválido '$CG_TARGET' (use aws o local)" ;; esac
}

is_apply() { [[ "$CG_MODE" == apply ]]; }

# is_approved <role>: billable operations need --apply and the role in --approve (or "all").
is_approved() {
  is_apply && [[ ",$CG_APPROVED," == *",$1,"* || ",$CG_APPROVED," == *",all,"* ]]
}

cg_load_config() {
  set -a
  # shellcheck source=../../config/aws.env
  . "$INFRA_DIR/config/aws.env"
  if [[ -f "$INFRA_DIR/config/operator.local.env" ]]; then
    # shellcheck disable=SC1091
    . "$INFRA_DIR/config/operator.local.env"
  fi
  set +a
}

cg_validate_env() {
  case "${1:-}" in dev | stage | prod) ;; *) die "Ambiente inválido '${1:-}': use dev, stage o prod" ;; esac
}

# cg_env_value <env> <VAR>: non-secret setting from infra/config/envs/<env>.env
cg_env_value() {
  cg_validate_env "$1"
  (
    # shellcheck disable=SC1090
    . "$INFRA_DIR/config/envs/$1.env"
    printf '%s' "${!2:?$2 no está definido en infra/config/envs/$1.env}"
  )
}

require_cmd() {
  local c
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "Falta la herramienta requerida: $c"; done
}

# nz <value>: true for a real value (AWS CLI prints None for missing fields).
nz() { [[ -n "${1:-}" && "$1" != None && "$1" != null ]]; }

# cg_mask <text>: hides the last octet of IPv4 addresses in messages and logs.
cg_mask() { sed -E 's/([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+/\1.x/g' <<<"$1"; }

# confirm <phrase> <question>: destructive operations require typing the exact phrase
# (or exporting CG_CONFIRM with it for non-interactive runs).
confirm() {
  local answer
  [[ "${CG_CONFIRM:-}" == "$1" ]] && return 0
  [[ -t 0 ]] || die "Se requiere confirmación: ejecute en una terminal interactiva o exporte CG_CONFIRM='$1'."
  read -r -p "$2 Escriba '$1' para continuar: " answer
  [[ "$answer" == "$1" ]] || die "Confirmación no válida: no se realizó ningún cambio."
}

# cg_start_log <name>: copies the output of the run to infra/logs/<name>-<timestamp>.log.
# Child scripts started by bootstrap-all.sh reuse the parent's log.
cg_start_log() {
  [[ -n "${CG_LOG_FILE:-}" ]] && return 0
  mkdir -p "$INFRA_DIR/logs"
  CG_LOG_FILE="$INFRA_DIR/logs/$1-$(date -u +%Y%m%dT%H%M%SZ).log"
  export CG_LOG_FILE
  exec > >(tee -a "$CG_LOG_FILE") 2>&1
  info "registro de la ejecución: infra/logs/${CG_LOG_FILE##*/} (modo $CG_MODE, destino $CG_TARGET)"
}

cg_summary() {
  log SUMMARY "$1 created=$CG_CREATED updated=$CG_UPDATED unchanged=$CG_UNCHANGED planned=$CG_PLANNED"
  if [[ -n "${CG_COUNTERS_FILE:-}" ]]; then
    printf '%s %d %d %d %d\n' "$1" "$CG_CREATED" "$CG_UPDATED" "$CG_UNCHANGED" "$CG_PLANNED" >>"$CG_COUNTERS_FILE"
  fi
}

aws_() { aws --region "$AWS_REGION" "$@"; }

# ---------------------------------------------------------------------------------------
# Secrets. Backends: SSM Parameter Store (target aws) or files under ~/.circleguard/secrets
# (target local, outside the repository and outside OneDrive). Values only travel through
# pipes and variables; they are never echoed.
# ---------------------------------------------------------------------------------------

# cg_generate <generator>: writes a fresh random value to stdout (pipe it, never echo it).
cg_generate() {
  python3 -c '
import secrets, string, sys
kind = sys.argv[1]
rnd = secrets.SystemRandom()
if kind == "password":
    rest = ([rnd.choice(string.ascii_uppercase) for _ in range(5)]
            + [rnd.choice(string.ascii_lowercase) for _ in range(14)]
            + [rnd.choice(string.digits) for _ in range(6)]
            + [rnd.choice("-_.") for _ in range(4)])
    rnd.shuffle(rest)
    sys.stdout.write(rnd.choice(string.ascii_letters) + "".join(rest))
elif kind == "username":
    sys.stdout.write("cg_" + secrets.token_hex(4))
elif kind == "hex32":
    sys.stdout.write(secrets.token_hex(32))
elif kind == "hex8":
    sys.stdout.write(secrets.token_hex(8))
else:
    sys.exit("generador desconocido: " + kind)
' "$1"
}

cg_secret_param() { printf '/%s/%s/%s' "$PROJECT" "$1" "$2"; }

# cg_catalog: "<scope> <NAME> <generator>" lines with the env scope expanded per environment.
cg_catalog() {
  local scope name gen e
  while read -r scope name gen _; do
    [[ -z "${scope:-}" || "$scope" == \#* ]] && continue
    if [[ "$scope" == env ]]; then
      for e in "${CG_ENVS[@]}"; do echo "$e $name $gen"; done
    else
      echo "$scope $name $gen"
    fi
  done <"$INFRA_DIR/config/secrets.catalog"
}

# cg_secret_exists <scope> <NAME>
cg_secret_exists() {
  local err
  if [[ "$CG_TARGET" == local ]]; then
    [[ -s "$CG_LOCAL_HOME/secrets/$1/$2" ]]
    return
  fi
  if err=$(aws_ ssm get-parameter --name "$(cg_secret_param "$1" "$2")" --query Parameter.Version --output text 2>&1 >/dev/null); then
    return 0
  fi
  [[ "$err" == *ParameterNotFound* ]] && return 1
  die "No se pudo consultar $(cg_secret_param "$1" "$2") en SSM: ${err%%$'\n'*}"
}

# cg_secret_create <scope> <NAME>: value read from stdin. Creates only; never overwrites.
cg_secret_create() {
  if [[ "$CG_TARGET" == local ]]; then
    install -d -m 700 "$CG_LOCAL_HOME" "$CG_LOCAL_HOME/secrets" "$CG_LOCAL_HOME/secrets/${1%%/*}" "$CG_LOCAL_HOME/secrets/$1"
    (umask 077 && set -o noclobber && cat >"$CG_LOCAL_HOME/secrets/$1/$2")
    return
  fi
  (
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    python3 -c '
import json, sys
name, story, project, scope, out = sys.argv[1:6]
request = {
    "Name": name, "Value": sys.stdin.read(), "Type": "SecureString", "Tier": "Standard",
    "Description": "CircleGuard " + story + " " + scope + " (infra/bootstrap-secrets.sh)",
    "Tags": [{"Key": "Project", "Value": project}, {"Key": "Story", "Value": story},
             {"Key": "ManagedBy", "Value": "infra-bootstrap"}],
}
with open(out, "w") as fh:
    json.dump(request, fh)
' "$(cg_secret_param "$1" "$2")" "$STORY" "$PROJECT" "$1" "$tmp/request.json"
    aws_ ssm put-parameter --cli-input-json "file://$tmp/request.json" >/dev/null
  )
}

# cg_secret_get <scope> <NAME>: prints the value; capture it in a variable or pipe it.
cg_secret_get() {
  if [[ "$CG_TARGET" == local ]]; then
    cat "$CG_LOCAL_HOME/secrets/$1/$2"
    return
  fi
  aws_ ssm get-parameter --with-decryption --name "$(cg_secret_param "$1" "$2")" --query Parameter.Value --output text
}

# cg_render_env <scope> <NAME...>: NAME=value lines for a remote .env (pipe it, never echo it).
cg_render_env() {
  local scope=$1 name value
  shift
  for name in "$@"; do
    cg_secret_exists "$scope" "$name" || die "Falta el secreto $(cg_secret_param "$scope" "$name"): ejecute infra/bootstrap-secrets.sh --apply"
    value=$(cg_secret_get "$scope" "$name")
    printf '%s=%s\n' "$name" "$value"
  done
}
