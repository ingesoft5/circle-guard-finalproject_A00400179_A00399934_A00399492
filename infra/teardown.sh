#!/usr/bin/env bash
# HU-01 · Stops or removes ONLY the resources created by the HU-01 scripts (tags
# Project=circleguard and ManagedBy=infra-bootstrap). Like every other script, the default mode
# is --plan: it lists the affected resources and what would be done, without changing anything.
#   --stop --apply      stops the instances (data kept; only the EBS volumes keep being billed)
#   --destroy --apply   terminates the instances (their volumes and DATA are deleted) and removes
#                       the network and the key pairs; also requires typing a confirmation phrase
#   --purge-secrets     with --destroy, also deletes /circleguard/* from SSM (second phrase)
# --target local stops or removes the local tool stacks; Docker volumes are always kept.

# shellcheck source=bootstrap/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/aws.sh
source "$INFRA_DIR/bootstrap/lib/aws.sh"

usage() {
  cat <<'EOF'
Uso: infra/teardown.sh (--stop | --destroy [--purge-secrets]) [--plan | --apply [--yes]] [--target aws|local]
  Sin --apply (por defecto --plan) solo muestra el inventario y lo que haría.
  --stop --apply     detiene las instancias de HU-01 (conserva datos; el EBS se sigue cobrando).
  --destroy --apply  elimina instancias (y sus datos), red y pares de llaves de HU-01.
                     Exige escribir 'DESTRUIR circleguard' (o exportar CG_CONFIRM con esa frase).
  --purge-secrets    junto con --destroy, borra también los secretos /circleguard/* de SSM.
  --target local     detiene o elimina los stacks locales; los volúmenes Docker se conservan.
EOF
}

inventory() {
  info "recursos de $PROJECT ($STORY) en $AWS_REGION:"
  aws_ ec2 describe-instances --filters "${FILTERS[@]}" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,InstanceId,InstanceType,State.Name]' --output text | sed 's/^/  instancia  /' >&2
  aws_ ec2 describe-volumes --filters "${FILTERS[@]}" --query 'Volumes[].[Tags[?Key==`Name`]|[0].Value,VolumeId,Size,State]' --output text | sed 's/^/  volumen    /' >&2
  aws_ ec2 describe-security-groups --filters "${FILTERS[@]}" --query 'SecurityGroups[].[GroupName,GroupId]' --output text | sed 's/^/  sg         /' >&2
  aws_ ec2 describe-subnets --filters "${FILTERS[@]}" --query 'Subnets[].[Tags[?Key==`Name`]|[0].Value,SubnetId]' --output text | sed 's/^/  subred     /' >&2
  aws_ ec2 describe-route-tables --filters "${FILTERS[@]}" --query 'RouteTables[].[Tags[?Key==`Name`]|[0].Value,RouteTableId]' --output text | sed 's/^/  rutas      /' >&2
  aws_ ec2 describe-internet-gateways --filters "${FILTERS[@]}" --query 'InternetGateways[].[Tags[?Key==`Name`]|[0].Value,InternetGatewayId]' --output text | sed 's/^/  igw        /' >&2
  aws_ ec2 describe-vpcs --filters "${FILTERS[@]}" --query 'Vpcs[].[Tags[?Key==`Name`]|[0].Value,VpcId]' --output text | sed 's/^/  vpc        /' >&2
  aws_ ec2 describe-key-pairs --filters "${FILTERS[@]}" --query 'KeyPairs[].[KeyName]' --output text | sed 's/^/  llave      /' >&2
  info "  secretos en SSM bajo /$PROJECT: $(aws_ ssm get-parameters-by-path --path "/$PROJECT" --recursive --query 'length(Parameters)' --output text)"
}

instance_ids() {
  aws_ ec2 describe-instances --filters "${FILTERS[@]}" "Name=instance-state-name,Values=${1}" \
    --query 'Reservations[].Instances[].InstanceId' --output text
}

stop_aws() {
  local ids id
  inventory
  ids=$(instance_ids pending,running)
  if [[ -z "$ids" ]]; then
    unchanged "no hay instancias de $PROJECT en ejecución"
    return
  fi
  if ! is_apply; then
    planned "detener las instancias: $ids (use --apply para hacerlo)"
    return
  fi
  $CG_ASSUME_YES || confirm DETENER "Se detendrán: $ids."
  # shellcheck disable=SC2086
  aws_ ec2 stop-instances --instance-ids $ids >/dev/null
  # shellcheck disable=SC2086
  aws_ ec2 wait instance-stopped --instance-ids $ids
  for id in $ids; do cg_ledger stop - "$id" - -; done
  updated "instancias detenidas: $ids (los volúmenes EBS se conservan y se siguen cobrando)"
}

destroy_aws() {
  local ids id vpc sg rule_ids rtb assoc igw subnet key names
  inventory
  if ! is_apply; then
    planned "terminar instancias (y sus volúmenes), revocar reglas y eliminar grupos de seguridad, tabla de rutas, internet gateway, subredes, VPC y pares de llaves de $PROJECT"
    if [[ " ${CG_ARGS[*]} " == *" --purge-secrets "* ]]; then planned "borrar los secretos /$PROJECT/* de SSM"; fi
    info "modo --plan: no se eliminó nada (use --apply y confirme la frase para ejecutar)"
    return
  fi
  warn "--destroy elimina las instancias y sus volúmenes: se PIERDEN los datos de Jenkins, SonarQube y Nexus."
  confirm "DESTRUIR $PROJECT" "Esta operación no se puede deshacer."

  ids=$(instance_ids pending,running,stopping,stopped)
  if [[ -n "$ids" ]]; then
    # shellcheck disable=SC2086
    aws_ ec2 terminate-instances --instance-ids $ids >/dev/null
    # shellcheck disable=SC2086
    aws_ ec2 wait instance-terminated --instance-ids $ids
    for id in $ids; do cg_ledger terminate - "$id" - -; done
    updated "instancias terminadas: $ids"
  fi
  vpc=$(aws_ ec2 describe-vpcs --filters "${FILTERS[@]}" --query 'Vpcs[0].VpcId' --output text)
  # Security groups reference each other: revoke every rule first, then delete them.
  for sg in $(aws_ ec2 describe-security-groups --filters "${FILTERS[@]}" --query 'SecurityGroups[].GroupId' --output text); do
    rule_ids=$(aws_ ec2 describe-security-group-rules --filters "Name=group-id,Values=$sg" --query 'SecurityGroupRules[?!IsEgress].SecurityGroupRuleId' --output text)
    # shellcheck disable=SC2086
    [[ -n "$rule_ids" ]] && aws_ ec2 revoke-security-group-ingress --group-id "$sg" --security-group-rule-ids $rule_ids >/dev/null
    rule_ids=$(aws_ ec2 describe-security-group-rules --filters "Name=group-id,Values=$sg" --query 'SecurityGroupRules[?IsEgress].SecurityGroupRuleId' --output text)
    # shellcheck disable=SC2086
    [[ -n "$rule_ids" ]] && aws_ ec2 revoke-security-group-egress --group-id "$sg" --security-group-rule-ids $rule_ids >/dev/null
  done
  for sg in $(aws_ ec2 describe-security-groups --filters "${FILTERS[@]}" --query 'SecurityGroups[].GroupId' --output text); do
    aws_ ec2 delete-security-group --group-id "$sg"
    updated "grupo de seguridad eliminado: $sg"
  done
  for rtb in $(aws_ ec2 describe-route-tables --filters "${FILTERS[@]}" --query 'RouteTables[].RouteTableId' --output text); do
    for assoc in $(aws_ ec2 describe-route-tables --route-table-ids "$rtb" --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' --output text); do
      aws_ ec2 disassociate-route-table --association-id "$assoc"
    done
    aws_ ec2 delete-route-table --route-table-id "$rtb"
    updated "tabla de rutas eliminada: $rtb"
  done
  for igw in $(aws_ ec2 describe-internet-gateways --filters "${FILTERS[@]}" --query 'InternetGateways[].InternetGatewayId' --output text); do
    if nz "$vpc"; then aws_ ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc" 2>/dev/null || true; fi
    aws_ ec2 delete-internet-gateway --internet-gateway-id "$igw"
    updated "internet gateway eliminado: $igw"
  done
  for subnet in $(aws_ ec2 describe-subnets --filters "${FILTERS[@]}" --query 'Subnets[].SubnetId' --output text); do
    aws_ ec2 delete-subnet --subnet-id "$subnet"
    updated "subred eliminada: $subnet"
  done
  if nz "$vpc"; then
    aws_ ec2 delete-vpc --vpc-id "$vpc"
    updated "vpc eliminada: $vpc"
  fi
  for key in $(aws_ ec2 describe-key-pairs --filters "${FILTERS[@]}" --query 'KeyPairs[].KeyName' --output text); do
    aws_ ec2 delete-key-pair --key-name "$key" >/dev/null
    updated "par de llaves EC2 eliminado: $key (la llave privada local y su copia en SSM se conservan)"
  done

  if [[ " ${CG_ARGS[*]} " == *" --purge-secrets "* ]]; then
    confirm "BORRAR SECRETOS $PROJECT" "Se borrarán TODOS los secretos /$PROJECT/* de SSM."
    names=$(aws_ ssm get-parameters-by-path --path "/$PROJECT" --recursive --query 'Parameters[].Name' --output text | tr '\t' '\n')
    while read -r batch; do
      [[ -n "$batch" ]] || continue
      # shellcheck disable=SC2086
      aws_ ssm delete-parameters --names $batch >/dev/null
    done < <(xargs -n 10 <<<"$names")
    updated "secretos /$PROJECT/* eliminados de SSM"
  else
    info "los secretos de SSM se conservan (use --purge-secrets para borrarlos)"
  fi
}

local_stacks() {
  local tool dir project
  for tool in jenkins sonarqube nexus; do
    dir="$CG_LOCAL_HOME/local/$tool"
    [[ -f "$dir/docker-compose.yml" ]] || continue
    project="circleguard-$tool"
    if [[ "$1" == stop ]]; then
      if [[ -z "$(docker ps -q --filter "label=com.docker.compose.project=$project")" ]]; then
        unchanged "stack local $project ya detenido"
        continue
      fi
      if ! is_apply; then
        planned "detener el stack local $project (use --apply)"
        continue
      fi
      (cd "$dir" && docker compose stop) >&2
      updated "stack local $project detenido"
    elif ! is_apply; then
      planned "eliminar los contenedores del stack local $project, conservando sus volúmenes (use --apply)"
    else
      (cd "$dir" && docker compose down) >&2
      updated "stack local $project eliminado (sus volúmenes Docker se conservan)"
    fi
  done
}

cg_parse_flags "$@"
cg_load_config
# Only resources created by the HU-01 scripts carry both tags.
FILTERS=("Name=tag:Project,Values=$PROJECT" "Name=tag:ManagedBy,Values=infra-bootstrap")
ACTION=""
for arg in "${CG_ARGS[@]}"; do
  case "$arg" in
    --stop) ACTION=stop ;;
    --destroy) ACTION=destroy ;;
    --purge-secrets) ;;
    *) die "opción desconocida: $arg" ;;
  esac
done
[[ -n "$ACTION" ]] || { usage; exit 1; }
cg_start_log "teardown-$ACTION"
if [[ "$CG_TARGET" == local ]]; then
  require_cmd docker
  local_stacks "$ACTION"
else
  # Stopping only lowers costs and keeps data: the reader role may do it. Destroying needs the
  # teardown role, which only the teardown user can assume (lib/session.sh).
  if [[ "$ACTION" == destroy ]] && is_apply; then cg_aws_use destroy; else cg_aws_use read; fi
  cg_aws_preflight
  if [[ "$ACTION" == stop ]]; then stop_aws; else destroy_aws; fi
fi
cg_summary "teardown-$ACTION"
