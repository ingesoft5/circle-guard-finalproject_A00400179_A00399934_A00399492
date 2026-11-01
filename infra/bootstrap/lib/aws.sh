#!/usr/bin/env bash
# AWS helpers of the HU-01 scripts: identity checks, tags, lookups and roles.
# Requires common.sh to be sourced first.

# shellcheck source=session.sh
source "$CG_LIB_DIR/session.sh"
# shellcheck source=budget.sh
source "$CG_LIB_DIR/budget.sh"

# shellcheck disable=SC2034 # used by the scripts that source this library
CG_ROLES=(jenkins sonarqube nexus env-dev env-stage env-prod)

# cg_aws_preflight: validates tools, the identity of the capability the run needs (by default
# read for --plan and operate for --apply; see lib/session.sh), region and zone. The scripts
# never prompt nor handle passwords or MFA codes: those are typed only on the AWS sign-in page.
cg_aws_preflight() {
  require_cmd python3 curl
  local account state
  [[ -n "$CG_CAPABILITY" ]] || if is_apply; then cg_aws_use operate; else cg_aws_use read; fi
  cg_aws_identity
  account=$(cut -d: -f5 <<<"$CG_AWS_ARN")
  state=$(aws_ ec2 describe-availability-zones --zone-names "$AWS_AZ" --query 'AvailabilityZones[0].State' --output text 2>/dev/null) ||
    die "No se pudo validar la zona $AWS_AZ en $AWS_REGION (región deshabilitada o sin permiso ec2:DescribeAvailabilityZones)."
  [[ "$state" == available ]] || die "La zona $AWS_AZ no está disponible (estado: $state)."
  info "identidad AWS ${CG_AWS_ARN##*:} · capacidad $CG_CAPABILITY · cuenta ****${account: -4} · región $AWS_REGION · zona $AWS_AZ"
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
# With the reader role a denial is expected: the check is then left for the operator role.
cg_dry_run() {
  local out
  if out=$(aws_ ec2 "$@" --dry-run 2>&1); then return 0; fi
  if [[ "$out" == *DryRunOperation* ]]; then
    info "permiso verificado con --dry-run: ec2 $1"
    return 0
  fi
  if [[ "$CG_CAPABILITY" == read && "$out" == *UnauthorizedOperation* ]]; then
    info "dry-run de ec2 $1 no verificable con el rol de lectura: se valida con el rol de operación"
    return 0
  fi
  die "dry-run de ec2 $1 rechazado: ${out%%$'\n'*}"
}

cg_role_tier() {
  case "$1" in
    jenkins | sonarqube | nexus) echo tools ;;
    env-dev | env-stage | env-prod) echo "${1#env-}" ;;
    *) die "Rol desconocido: $1" ;;
  esac
}

cg_role_type() {
  case "$1" in
    jenkins) echo "$JENKINS_INSTANCE_TYPE" ;;
    sonarqube) echo "$SONARQUBE_INSTANCE_TYPE" ;;
    nexus) echo "$NEXUS_INSTANCE_TYPE" ;;
    env-*) cg_env_value "${1#env-}" ENV_INSTANCE_TYPE ;;
  esac
}

cg_role_volume() {
  case "$1" in
    jenkins) echo "$JENKINS_VOLUME_GB" ;;
    sonarqube) echo "$SONARQUBE_VOLUME_GB" ;;
    nexus) echo "$NEXUS_VOLUME_GB" ;;
    env-*) cg_env_value "${1#env-}" ENV_VOLUME_GB ;;
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
