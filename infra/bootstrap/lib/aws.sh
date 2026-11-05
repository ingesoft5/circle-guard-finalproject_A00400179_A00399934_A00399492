#!/usr/bin/env bash
# AWS helpers of the HU-01 scripts: identity checks, tags, lookups and roles.
# Requires common.sh to be sourced first.

# shellcheck source=session.sh
source "$CG_LIB_DIR/session.sh"
# shellcheck source=budget.sh
source "$CG_LIB_DIR/budget.sh"

# Servers of HU-01 (topology B): "ci" runs Jenkins and SonarQube, "nexus" runs Nexus and the
# registry. Environment servers (env-dev, env-stage, env-prod) are added by cg_init_roles only for
# the environments listed in ENV_SERVERS (empty by default: network isolation only).
# shellcheck disable=SC2034 # used by the scripts that source this library
CG_ROLES=(ci nexus)

# cg_init_roles: called by cg_load_config once infra/config/aws.env is loaded. Validates the
# settings that select servers and the registry, and completes CG_ROLES.
cg_init_roles() {
  local e
  CG_ROLES=(ci nexus)
  for e in ${ENV_SERVERS//,/ }; do
    cg_validate_env "$e"
    [[ " ${CG_ROLES[*]} " == *" env-$e "* ]] || CG_ROLES+=("env-$e")
  done
  case "${REGISTRY_BACKEND:-}" in
    distribution | nexus) ;;
    *) die "REGISTRY_BACKEND inválido '${REGISTRY_BACKEND:-}' en infra/config/aws.env (use distribution o nexus)" ;;
  esac
}

# cg_registry_tools: tools deployed on the nexus server, in the order that frees and then takes
# the registry port (the backend not in use is retired first).
cg_registry_tools() {
  if [[ "$REGISTRY_BACKEND" == distribution ]]; then echo nexus registry; else echo registry nexus; fi
}

# cg_aws_preflight: validates tools, the identity of the capability the run needs (by default
# read for --plan and operate for --apply; see lib/session.sh), region and zone. The scripts
# never prompt nor handle passwords or MFA codes: those are typed only on the AWS sign-in page.
cg_aws_preflight() {
  require_cmd python3 curl
  local account state
  [[ -n "$CG_CAPABILITY" ]] || if is_apply; then cg_aws_use operate; else cg_aws_use read; fi
  cg_aws_identity
  account=$(cut -d: -f5 <<<"$CG_AWS_ARN")
  info "identidad AWS ${CG_AWS_ARN##*:} · capacidad $CG_CAPABILITY · cuenta ****${account: -4} · región $AWS_REGION · zona $AWS_AZ"
  state=$(aws_ ec2 describe-availability-zones --zone-names "$AWS_AZ" --query 'AvailabilityZones[0].State' --output text 2>&1) ||
    die "No se pudo validar la zona $AWS_AZ con ${CG_AWS_ARN##*:}: $(cg_aws_error "$state")"
  [[ "$state" == available ]] || die "La zona $AWS_AZ no está disponible (estado: $state)."
}

# cg_aws_error <output>: "<code> en <operation>: <reason>" of a failed AWS CLI call (an MFA
# failure of the role shows up as AccessDenied en AssumeRole), without ARNs nor account ids.
# Other output: its first non-empty line (the CLI starts its errors with an empty line).
cg_aws_error() {
  { grep -m1 'An error occurred' <<<"$1" || grep -m1 -v '^[[:space:]]*$' <<<"$1" || true; } |
    sed -E 's/^.*An error occurred \(([A-Za-z.]+)\) when calling the ([A-Za-z]+) operation: /\1 en \2: /
      s/You are not authorized to perform this operation\. User: .* is not authorized to perform: [^ ]+ //
      s/[0-9]{12}/************/g'
}

# cg_admin_cidrs: CIDRs allowed to reach SSH and the tool UIs (one per line).
cg_admin_cidrs() {
  local ip
  if [[ -n "${ADMIN_CIDRS:-}" ]]; then
    sed -E 's/[, ]+/\n/g' <<<"$ADMIN_CIDRS" | sed '/^$/d'
    return
  fi
  ip=$(curl -fsS --max-time 10 https://checkip.amazonaws.com | tr -d '[:space:]') ||
    die "No se pudo detectar la IP pública del operador: defina ADMIN_CIDRS en infra/config/operator.local.env."
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "IP pública inválida; defina ADMIN_CIDRS."
  echo "$ip/32"
}

# Tags shared by every resource of HU-01 (also used by teardown.sh and for cost tracking).
cg_tags() {
  printf '{Key=Name,Value=%s},{Key=Project,Value=%s},{Key=Story,Value=%s},{Key=ManagedBy,Value=infra-bootstrap},{Key=Role,Value=%s},{Key=Environment,Value=%s}' \
    "$1" "$PROJECT" "$STORY" "$2" "$3"
}
cg_tag_spec() { printf 'ResourceType=%s,Tags=[%s]' "$1" "$(cg_tags "$2" "$3" "$4")"; }

# cg_one <description> <ids>: the single id, None when absent; stops on duplicates instead of
# picking one at random (a duplicate means somebody created resources outside the scripts).
cg_one() {
  local count
  count=$(wc -w <<<"$2")
  ((count <= 1)) || die "Hay $count recursos '$1' duplicados ($2): revíselos manualmente; no se elige uno al azar."
  if ((count == 1)); then echo "$2" | tr -d '[:space:]'; else echo None; fi
}

# cg_find <describe-command> <list query> <Name tag>: id of the tagged resource, or None.
cg_find() {
  cg_one "$3" "$(aws_ ec2 "$1" --filters "Name=tag:Project,Values=$PROJECT" "Name=tag:Name,Values=$3" --query "$2" --output text)"
}

# is_real <id>: a real AWS id (not a planned placeholder).
is_real() { [[ "${1:-}" =~ ^[a-z]+-[0-9a-f]+$ ]]; }

# cg_dry_run <ec2 subcommand> [args]: validates permissions and parameters without creating.
# Only the reader role may get a denial (it has no write permissions by design): the check is
# then left for the operator role. Any other identity, including the operator role selected with
# CG_AWS_PROFILE in a plan, fails on UnauthorizedOperation like on any other error.
cg_dry_run() {
  local out
  if out=$(aws_ ec2 "$@" --dry-run 2>&1); then return 0; fi
  if [[ "$out" == *DryRunOperation* ]]; then
    info "permiso verificado con --dry-run: ec2 $1"
    return 0
  fi
  if [[ "${CG_AWS_ARN:-}" == *":assumed-role/circleguard-hu01-reader/"* && "$out" == *UnauthorizedOperation* ]]; then
    info "dry-run de ec2 $1 no verificable con el rol de lectura: se valida con el rol de operación"
    return 0
  fi
  die "dry-run de ec2 $1 rechazado${CG_AWS_ARN:+ con ${CG_AWS_ARN##*:}}: $(cg_aws_error "$out")"
}

cg_role_tier() {
  case "$1" in
    ci | nexus | jenkins | sonarqube | registry) echo tools ;;
    env-dev | env-stage | env-prod) echo "${1#env-}" ;;
    *) die "Rol desconocido: $1" ;;
  esac
}

# cg_tool_host <tool>: server role that runs a tool.
cg_tool_host() {
  case "$1" in
    jenkins | sonarqube) echo ci ;;
    nexus | registry) echo nexus ;;
    *) die "Herramienta desconocida: $1" ;;
  esac
}

cg_role_type() {
  case "$1" in
    ci) echo "$CI_INSTANCE_TYPE" ;;
    nexus) echo "$NEXUS_INSTANCE_TYPE" ;;
    env-*) cg_env_value "${1#env-}" ENV_INSTANCE_TYPE ;;
    *) die "Rol sin servidor: $1" ;;
  esac
}

cg_role_volume() {
  case "$1" in
    ci) echo "$CI_VOLUME_GB" ;;
    nexus) echo "$NEXUS_VOLUME_GB" ;;
    env-*) cg_env_value "${1#env-}" ENV_VOLUME_GB ;;
    *) die "Rol sin servidor: $1" ;;
  esac
}

# cg_type_vcpu <instance type>: vCPU of the types the operator role may launch.
cg_type_vcpu() {
  case "$1" in
    t3.small | c7i-flex.large | m7i-flex.large) echo 2 ;;
    *) die "Tipo de instancia sin vCPU conocidas: $1" ;;
  esac
}

cg_instance_name() { echo "$PROJECT-$1"; }
cg_sg_name() { echo "$PROJECT-sg-$1"; }

cg_sg_id() {
  cg_one "$(cg_sg_name "$1")" "$(aws_ ec2 describe-security-groups --filters "Name=tag:Project,Values=$PROJECT" \
    "Name=group-name,Values=$(cg_sg_name "$1")" --query 'SecurityGroups[].GroupId' --output text)"
}

# cg_find_instances <role> [states]: "id state type public-ip private-ip" per instance.
cg_find_instances() {
  aws_ ec2 describe-instances --filters "Name=tag:Project,Values=$PROJECT" "Name=tag:Role,Values=$1" \
    "Name=instance-state-name,Values=${2:-pending,running,stopping,stopped}" \
    --query 'Reservations[].Instances[].[InstanceId,State.Name,InstanceType,PublicIpAddress,PrivateIpAddress]' --output text
}
