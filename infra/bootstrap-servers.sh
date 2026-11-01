#!/usr/bin/env bash
# HU-01 · EC2 servers: jenkins, sonarqube and nexus, plus one host per environment (dev,
# stage, prod). BILLABLE. The default --plan mode prints the cost preview and validates
# permissions with --dry-run. Creating or starting an instance requires
#   --apply --approve <role>[,<role>...]   (or --approve all)
# Instances use Ubuntu 24.04, encrypted gp3 volumes, IMDSv2 and, on burstable T types, "standard"
# CPU credits (no surplus charges; flex types have no credits). Existing instances are never
# replaced or resized automatically.

# shellcheck source=bootstrap/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/aws.sh
source "$INFRA_DIR/bootstrap/lib/aws.sh"

usage() {
  cat <<'EOF'
Uso: infra/bootstrap-servers.sh [--plan | --apply --approve <roles>] | --prices
  --plan     (por defecto) muestra costos estimados y valida permisos con --dry-run.
  --apply --approve jenkins,sonarqube,...   crea o inicia SOLO los roles aprobados (FACTURABLE).
  --prices   consulta los precios vigentes en la AWS Pricing API (solo lectura) y termina.
Roles: jenkins sonarqube nexus env-dev env-stage env-prod (o "all").
EOF
}

price_hour() {
  local var="PRICE_HOUR_${1//[.-]/_}"
  [[ -n "${!var:-}" ]] || die "No hay precio de referencia para $1 en infra/config/aws.env"
  printf '%s' "${!var}"
}

cost_preview() {
  local role
  {
    for role in "${CG_ROLES[@]}"; do
      echo "$role $(cg_role_type "$role") $(cg_role_volume "$role") $(price_hour "$(cg_role_type "$role")")"
    done
  } | awk -v ip="$PRICE_IPV4_HOUR" -v gbm="$PRICE_EBS_GP3_GB_MONTH" -v date="$PRICES_REFERENCE_DATE" '
    BEGIN {
      printf "\nEstimación On-Demand (precios de referencia %s; verificar con --prices)\n", date
      printf "  %-10s %-10s %7s %9s %9s %10s %9s %10s\n", "rol", "tipo", "EC2 h", "IPv4 h", "EBS mes", "total h", "día 24h", "mes 730h"
    }
    {
      ebs = $3 * gbm; total = $4 + ip + ebs / 730
      printf "  %-10s %-10s %7.4f %9.4f %9.2f %10.4f %9.2f %10.2f\n", $1, $2, $4, ip, ebs, total, total * 24, total * 730
      sum += total; ebs_month += ebs
    }
    END {
      printf "  %-10s %-10s %7s %9s %9.2f %10.4f %9.2f %10.2f\n", "TOTAL", "", "", "", ebs_month, sum, sum * 24, sum * 730
      printf "  Detenidas solo se cobra el EBS: %.2f USD/día. Sin NAT Gateway ni Elastic IP.\n\n", ebs_month / 30.4
    }' >&2
}

# budget_preview: estimated cost of the instances this run would create or start, checked
# against the HU-01 budget before anything billable happens (local estimate: lib/budget.sh).
budget_preview() {
  local role rows state new projected=0
  for role in "${CG_ROLES[@]}"; do
    is_approved "$role" || continue
    rows=$(cg_find_instances "$role")
    state=$(awk '{ print $2 }' <<<"$rows")
    [[ "$state" == running || "$state" == pending ]] && continue
    if [[ -z "$rows" ]]; then new=1; else new=0; fi
    projected=$(awk -v p="$projected" -v h="$(price_hour "$(cg_role_type "$role")")" -v ip="$PRICE_IPV4_HOUR" \
      -v s="$SESSION_HOURS_ESTIMATE" -v new="$new" -v gib="$(cg_role_volume "$role")" -v gbm="$PRICE_EBS_GP3_GB_MONTH" \
      -v days="$EBS_RESERVE_DAYS" 'BEGIN { printf "%.4f", p + (h + ip) * s + new * gib * gbm / 730 * 24 * days }')
  done
  cg_budget_check "$projected" "esta ejecución (${SESSION_HOURS_ESTIMATE} h y EBS nuevo por ${EBS_RESERVE_DAYS} días)"
}

pricing_instance() {
  aws pricing get-products --region us-east-1 --service-code AmazonEC2 --output json --query PriceList \
    --filters "Type=TERM_MATCH,Field=instanceType,Value=$1" "Type=TERM_MATCH,Field=regionCode,Value=$AWS_REGION" \
    "Type=TERM_MATCH,Field=operatingSystem,Value=Linux" "Type=TERM_MATCH,Field=tenancy,Value=Shared" \
    "Type=TERM_MATCH,Field=preInstalledSw,Value=NA" "Type=TERM_MATCH,Field=capacitystatus,Value=Used" |
    python3 -c '
import json, sys
for item in json.load(sys.stdin):
    for term in json.loads(item)["terms"].get("OnDemand", {}).values():
        for dim in term["priceDimensions"].values():
            print(dim["pricePerUnit"]["USD"]); sys.exit()
print("?")'
}

show_prices() {
  local types t
  cg_aws_preflight
  types=$(for r in "${CG_ROLES[@]}"; do cg_role_type "$r"; echo; done | sort -u | sed '/^$/d')
  info "precios On-Demand vigentes en $AWS_REGION (AWS Pricing API, solo lectura):"
  for t in $types; do
    printf '  %-10s API=%s USD/h   referencia en aws.env=%s USD/h\n' "$t" "$(pricing_instance "$t")" "$(price_hour "$t")" >&2
  done
  printf '  gp3 y IPv4 pública: referencia %s USD/GB-mes y %s USD/h (ver la página de precios de EC2 y VPC)\n' \
    "$PRICE_EBS_GP3_GB_MONTH" "$PRICE_IPV4_HOUR" >&2
}

resolve_ami() {
  if nz "${AMI_ID:-}"; then
    AMI=$AMI_ID
  else
    AMI=$(aws_ ssm get-parameter --name "$AMI_SSM_PARAM" --query Parameter.Value --output text) ||
      die "No se pudo resolver la AMI de Ubuntu desde $AMI_SSM_PARAM"
  fi
  ROOT_DEVICE=$(aws_ ec2 describe-images --image-ids "$AMI" --query 'Images[0].RootDeviceName' --output text)
  nz "$ROOT_DEVICE" || die "La AMI $AMI no está disponible en $AWS_REGION."
  info "AMI Ubuntu 24.04: $AMI (dispositivo raíz $ROOT_DEVICE)"
}

# check_offerings: every configured instance type must be offered in the selected zone.
check_offerings() {
  local types t offered
  types=$(for r in "${CG_ROLES[@]}"; do cg_role_type "$r"; echo; done | sort -u | sed '/^$/d')
  for t in $types; do
    offered=$(aws_ ec2 describe-instance-type-offerings --location-type availability-zone \
      --filters "Name=location,Values=$AWS_AZ" "Name=instance-type,Values=$t" \
      --query 'InstanceTypeOfferings[0].InstanceType' --output text)
    [[ "$offered" == "$t" ]] || die "El tipo $t no se ofrece en $AWS_AZ: cambiar la zona o el tipo requiere autorización."
    info "tipo $t ofrecido en $AWS_AZ"
  done
}

is_burstable() { [[ "$1" == t[0-9]* ]]; } # T instances have CPU credits; flex instances do not

reconcile_instance() { # reconcile_instance <id> <name> <type>: free settings that must not drift
  local credits tokens
  if ! is_burstable "$3"; then
    unchanged "$2: $3 no usa créditos de CPU (sin cargos por ráfagas)"
  elif credits=$(aws_ ec2 describe-instance-credit-specifications --instance-ids "$1" \
    --query 'InstanceCreditSpecifications[0].CpuCredits' --output text) && [[ "$credits" == standard ]]; then
    unchanged "$2: créditos de CPU en modo standard (sin cargos por ráfagas)"
  elif is_apply; then
    aws_ ec2 modify-instance-credit-specification --instance-credit-specifications "InstanceId=$1,CpuCredits=standard" >/dev/null
    updated "$2: créditos de CPU cambiados a standard"
  else
    planned "$2: cambiar créditos de CPU a standard"
  fi
  tokens=$(aws_ ec2 describe-instances --instance-ids "$1" --query 'Reservations[0].Instances[0].MetadataOptions.HttpTokens' --output text)
  if [[ "$tokens" == required ]]; then
    unchanged "$2: IMDSv2 obligatorio"
  elif is_apply; then
    aws_ ec2 modify-instance-metadata-options --instance-id "$1" --http-tokens required --http-endpoint enabled >/dev/null
    updated "$2: IMDSv2 obligatorio"
  else
    planned "$2: exigir IMDSv2"
  fi
}

ensure_server() {
  local role=$1 tier type volume name rows id state current subnet sg key
  tier=$(cg_role_tier "$role")
  type=$(cg_role_type "$role")
  volume=$(cg_role_volume "$role")
  name=$(cg_instance_name "$role")
  rows=$(cg_find_instances "$role")
  [[ $(grep -c . <<<"$rows") -le 1 ]] || die "Hay más de una instancia con el rol $role: revísela manualmente (no se elimina nada automáticamente)."

  if [[ -n "$rows" ]]; then
    read -r id state current _ <<<"$rows"
    [[ "$current" == "$type" ]] ||
      warn "$name ($id) es $current y la configuración indica $type: no se cambia automáticamente (ver infra/README.md)."
    case "$state" in
      pending)
        aws_ ec2 wait instance-running --instance-ids "$id"
        unchanged "instancia $name ($id) en ejecución"
        reconcile_instance "$id" "$name" "$current"
        ;;
      running)
        unchanged "instancia $name ($id) $current en ejecución"
        reconcile_instance "$id" "$name" "$current"
        ;;
      stopping | stopped)
        if is_approved "$role"; then
          [[ "$state" == stopping ]] && aws_ ec2 wait instance-stopped --instance-ids "$id"
          aws_ ec2 start-instances --instance-ids "$id" >/dev/null
          cg_ledger start "$role" "$id" "$current" "$volume"
          aws_ ec2 wait instance-running --instance-ids "$id"
          updated "instancia $name ($id) iniciada (FACTURABLE desde ahora)"
          reconcile_instance "$id" "$name" "$current"
        else
          unchanged "instancia $name ($id) detenida (para iniciarla: --apply --approve $role)"
        fi
        ;;
    esac
    return 0
  fi

  subnet=$(cg_find describe-subnets 'Subnets[].SubnetId' "$PROJECT-subnet-$tier")
  sg=$(cg_sg_id "$role")
  key="$PROJECT-$tier"
  RUN_ARGS=(--image-id "$AMI" --instance-type "$type" --key-name "$key" --subnet-id "$subnet" --security-group-ids "$sg"
    --block-device-mappings "DeviceName=$ROOT_DEVICE,Ebs={VolumeSize=$volume,VolumeType=gp3,Encrypted=true,DeleteOnTermination=true}"
    --metadata-options "HttpTokens=required,HttpEndpoint=enabled,HttpPutResponseHopLimit=1"
    --instance-initiated-shutdown-behavior stop
    --tag-specifications "$(cg_tag_spec instance "$name" "$role" "$tier")" "$(cg_tag_spec volume "$name-root" "$role" "$tier")")
  if is_burstable "$type"; then RUN_ARGS+=(--credit-specification CpuCredits=standard); fi

  if ! is_approved "$role"; then
    if nz "$subnet" && nz "$sg"; then
      cg_dry_run run-instances "${RUN_ARGS[@]}"
    else
      info "dry-run de $role omitido: la red aún no existe (infra/bootstrap-network.sh --apply)"
    fi
    planned "crear la instancia $name ($type, $volume GiB gp3 cifrado) - FACTURABLE: requiere --apply --approve $role"
    return 0
  fi
  if ! nz "$subnet" || ! nz "$sg"; then die "Falta la red de $role: ejecute infra/bootstrap-network.sh --apply"; fi
  aws_ ec2 describe-key-pairs --key-names "$key" >/dev/null 2>&1 || die "Falta el par de llaves $key: ejecute infra/bootstrap-secrets.sh --apply"
  id=$(aws_ ec2 run-instances "${RUN_ARGS[@]}" --client-token "$PROJECT-$role-$subnet-$(date -u +%Y%m%d)" \
    --query 'Instances[0].InstanceId' --output text)
  cg_ledger run "$role" "$id" "$type" "$volume"
  aws_ ec2 wait instance-running --instance-ids "$id"
  created "instancia $name ($id) $type creada (FACTURABLE desde ahora)"
}

cg_parse_flags "$@"
cg_load_config
if [[ "${CG_ARGS[0]:-}" == --prices ]]; then
  show_prices
  exit 0
fi
cg_start_log bootstrap-servers
cg_aws_preflight
for role in ${CG_APPROVED//,/ }; do
  [[ "$role" == all ]] || cg_role_tier "$role" >/dev/null
done
cost_preview
budget_preview
check_offerings
resolve_ami
for role in "${CG_ROLES[@]}"; do ensure_server "$role"; done
cg_summary bootstrap-servers
