#!/usr/bin/env bash
# HU-01 · Network of the CircleGuard platform on AWS: one VPC, a public subnet per tier
# (tools, dev, stage, prod), internet gateway (no NAT Gateway), route table and
# least-privilege security groups. Environments never get rules towards each other.
#
# Idempotent: resources are found by their tags, created only when missing and reconciled
# when they drift. AWS does not bill VPCs, subnets, internet gateways, route tables or
# security groups.

# shellcheck source=bootstrap/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/aws.sh
source "$INFRA_DIR/bootstrap/lib/aws.sh"

usage() {
  cat <<'EOF'
Uso: infra/bootstrap-network.sh [--plan | --apply]
  --plan   (por defecto) muestra lo que haría y valida permisos con --dry-run; no crea nada.
  --apply  crea o corrige la VPC, las subredes, la tabla de rutas y los grupos de seguridad.
           No genera costos por hora.
EOF
}

SG_KEYS=(jenkins sonarqube nexus env-dev env-stage env-prod)
declare -A SUBNET_ID SG_ID
VPC_ID=""
IGW_ID=""

ensure_vpc() {
  local name="$PROJECT-vpc" id cidr dns
  id=$(cg_find describe-vpcs 'Vpcs[].VpcId' "$name")
  if nz "$id"; then
    cidr=$(aws_ ec2 describe-vpcs --vpc-ids "$id" --query 'Vpcs[0].CidrBlock' --output text)
    [[ "$cidr" == "$VPC_CIDR" ]] || die "La VPC $name ($id) tiene CIDR $cidr y se esperaba $VPC_CIDR: no se modifica una VPC existente."
    unchanged "vpc $name ($id) $cidr"
  elif is_apply; then
    id=$(aws_ ec2 create-vpc --cidr-block "$VPC_CIDR" --tag-specifications "$(cg_tag_spec vpc "$name" network shared)" \
      --query Vpc.VpcId --output text)
    aws_ ec2 wait vpc-available --vpc-ids "$id"
    created "vpc $name ($id) $VPC_CIDR"
  else
    cg_dry_run create-vpc --cidr-block "$VPC_CIDR" --tag-specifications "$(cg_tag_spec vpc "$name" network shared)"
    planned "crear vpc $name $VPC_CIDR"
    VPC_ID=new
    return
  fi
  dns=$(aws_ ec2 describe-vpc-attribute --vpc-id "$id" --attribute enableDnsHostnames --query EnableDnsHostnames.Value --output text)
  if [[ "$dns" == True ]]; then
    unchanged "vpc $name con nombres DNS"
  elif is_apply; then
    aws_ ec2 modify-vpc-attribute --vpc-id "$id" --enable-dns-hostnames '{"Value":true}'
    updated "vpc $name con nombres DNS"
  else
    planned "activar nombres DNS en $name"
  fi
  VPC_ID=$id
}

ensure_igw() {
  local name="$PROJECT-igw" id attached
  id=$(cg_find describe-internet-gateways 'InternetGateways[].InternetGatewayId' "$name")
  if nz "$id"; then
    unchanged "internet gateway $name ($id)"
  elif is_apply; then
    id=$(aws_ ec2 create-internet-gateway --tag-specifications "$(cg_tag_spec internet-gateway "$name" network shared)" \
      --query InternetGateway.InternetGatewayId --output text)
    created "internet gateway $name ($id)"
  else
    cg_dry_run create-internet-gateway --tag-specifications "$(cg_tag_spec internet-gateway "$name" network shared)"
    planned "crear internet gateway $name y adjuntarlo a la VPC"
    IGW_ID=new
    return
  fi
  attached=$(aws_ ec2 describe-internet-gateways --internet-gateway-ids "$id" --query 'InternetGateways[0].Attachments[0].VpcId' --output text)
  if [[ "$attached" == "$VPC_ID" ]]; then
    unchanged "internet gateway $name adjunto a $VPC_ID"
  elif nz "$attached"; then
    die "El internet gateway $name está adjunto a otra VPC ($attached)."
  elif is_apply && is_real "$VPC_ID"; then
    aws_ ec2 attach-internet-gateway --internet-gateway-id "$id" --vpc-id "$VPC_ID"
    updated "internet gateway $name adjuntado a $VPC_ID"
  else
    planned "adjuntar el internet gateway $name a la VPC"
  fi
  IGW_ID=$id
}

# ensure_subnet <tier> <cidr>: public subnet (IPv4 on launch gives egress without NAT Gateway).
ensure_subnet() {
  local tier=$1 cidr=$2 name="$PROJECT-subnet-$1" id actual az public
  if ! is_real "$VPC_ID"; then
    planned "crear subred $name $cidr ($AWS_AZ)"
    SUBNET_ID[$tier]=new
    return
  fi
  id=$(cg_find describe-subnets 'Subnets[].SubnetId' "$name")
  if nz "$id"; then
    read -r actual az <<<"$(aws_ ec2 describe-subnets --subnet-ids "$id" --query 'Subnets[0].[CidrBlock,AvailabilityZone]' --output text)"
    [[ "$actual" == "$cidr" && "$az" == "$AWS_AZ" ]] || die "La subred $name ($id) es $actual en $az; se esperaba $cidr en $AWS_AZ."
    unchanged "subred $name ($id) $cidr"
  elif is_apply; then
    id=$(aws_ ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$cidr" --availability-zone "$AWS_AZ" \
      --tag-specifications "$(cg_tag_spec subnet "$name" network "$tier")" --query Subnet.SubnetId --output text)
    created "subred $name ($id) $cidr"
  else
    cg_dry_run create-subnet --vpc-id "$VPC_ID" --cidr-block "$cidr" --availability-zone "$AWS_AZ" \
      --tag-specifications "$(cg_tag_spec subnet "$name" network "$tier")"
    planned "crear subred $name $cidr"
    SUBNET_ID[$tier]=new
    return
  fi
  public=$(aws_ ec2 describe-subnets --subnet-ids "$id" --query 'Subnets[0].MapPublicIpOnLaunch' --output text)
  if [[ "$public" == True ]]; then
    unchanged "subred $name asigna IPv4 pública al lanzar"
  elif is_apply; then
    aws_ ec2 modify-subnet-attribute --subnet-id "$id" --map-public-ip-on-launch
    updated "subred $name asigna IPv4 pública al lanzar"
  else
    planned "activar IPv4 pública al lanzar en $name"
  fi
  SUBNET_ID[$tier]=$id
}

ensure_route_table() {
  local name="$PROJECT-rt-public" id target tier assoc
  if ! is_real "$VPC_ID"; then
    planned "crear tabla de rutas $name (0.0.0.0/0 -> internet gateway) y asociar las 4 subredes"
    return
  fi
  id=$(cg_find describe-route-tables 'RouteTables[].RouteTableId' "$name")
  if nz "$id"; then
    unchanged "tabla de rutas $name ($id)"
  elif is_apply; then
    id=$(aws_ ec2 create-route-table --vpc-id "$VPC_ID" --tag-specifications "$(cg_tag_spec route-table "$name" network shared)" \
      --query RouteTable.RouteTableId --output text)
    created "tabla de rutas $name ($id)"
  else
    cg_dry_run create-route-table --vpc-id "$VPC_ID" --tag-specifications "$(cg_tag_spec route-table "$name" network shared)"
    planned "crear tabla de rutas $name y asociar las 4 subredes"
    return
  fi
  target=$(aws_ ec2 describe-route-tables --route-table-ids "$id" \
    --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].GatewayId | [0]" --output text)
  if [[ "$target" == "$IGW_ID" ]]; then
    unchanged "ruta 0.0.0.0/0 -> $IGW_ID"
  elif is_apply && is_real "$IGW_ID"; then
    if nz "$target"; then
      aws_ ec2 replace-route --route-table-id "$id" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID"
    else
      aws_ ec2 create-route --route-table-id "$id" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" >/dev/null
    fi
    updated "ruta 0.0.0.0/0 -> $IGW_ID"
  else
    planned "crear la ruta 0.0.0.0/0 hacia el internet gateway"
  fi
  for tier in tools "${CG_ENVS[@]}"; do
    if ! is_real "${SUBNET_ID[$tier]:-}"; then
      planned "asociar la subred $tier a $name"
      continue
    fi
    assoc=$(aws_ ec2 describe-route-tables --route-table-ids "$id" \
      --query "RouteTables[0].Associations[?SubnetId=='${SUBNET_ID[$tier]}'].RouteTableAssociationId | [0]" --output text)
    if nz "$assoc"; then
      unchanged "subred $tier asociada a $name"
    elif is_apply; then
      aws_ ec2 associate-route-table --route-table-id "$id" --subnet-id "${SUBNET_ID[$tier]}" >/dev/null
      updated "subred $tier asociada a $name"
    else
      planned "asociar la subred $tier a $name"
    fi
  done
}

sg_description() {
  case "$1" in
    jenkins) echo "CircleGuard HU-01 - Jenkins" ;;
    sonarqube) echo "CircleGuard HU-01 - SonarQube" ;;
    nexus) echo "CircleGuard HU-01 - Nexus Repository" ;;
    env-*) echo "CircleGuard HU-01 - environment ${1#env-} (isolated)" ;;
  esac
}

ensure_sg() {
  local key=$1 name id tier
  name=$(cg_sg_name "$key")
  tier=$(cg_role_tier "$key")
  if ! is_real "$VPC_ID"; then
    planned "crear grupo de seguridad $name"
    SG_ID[$key]=new
    return
  fi
  id=$(cg_sg_id "$key")
  if nz "$id"; then
    unchanged "grupo de seguridad $name ($id)"
  elif is_apply; then
    id=$(aws_ ec2 create-security-group --vpc-id "$VPC_ID" --group-name "$name" --description "$(sg_description "$key")" \
      --tag-specifications "$(cg_tag_spec security-group "$name" "$key" "$tier")" --query GroupId --output text)
    created "grupo de seguridad $name ($id)"
  else
    cg_dry_run create-security-group --vpc-id "$VPC_ID" --group-name "$name" --description "$(sg_description "$key")" \
      --tag-specifications "$(cg_tag_spec security-group "$name" "$key" "$tier")"
    planned "crear grupo de seguridad $name"
    SG_ID[$key]=new
    return
  fi
  SG_ID[$key]=$id
}

# desired_rules: "<sg key> <in|out> <tcp port> <cidr:X|sg:KEY>" lines. Everything not listed
# is denied: no rule ever connects two environments, and the tool UIs (plain HTTP) are never
# opened to the Internet: administrators reach them through an SSH tunnel (infra/tunnel.sh).
desired_rules() {
  local c k e
  for c in "${ADMIN[@]}"; do
    for k in "${SG_KEYS[@]}"; do echo "$k in 22 cidr:$c"; done
  done
  echo "sonarqube in $SONARQUBE_HTTP_PORT sg:jenkins"
  echo "nexus in $NEXUS_HTTP_PORT sg:jenkins"
  echo "nexus in $NEXUS_DOCKER_PORT sg:jenkins"
  for e in "${CG_ENVS[@]}"; do
    echo "env-$e in 22 sg:jenkins"
    echo "nexus in $NEXUS_DOCKER_PORT sg:env-$e"
  done
  # Egress: package repositories and registries (HTTP/HTTPS) plus the internal flows above.
  # DNS, NTP and instance metadata are not filtered by security groups.
  for k in "${SG_KEYS[@]}"; do
    echo "$k out 80 cidr:0.0.0.0/0"
    echo "$k out 443 cidr:0.0.0.0/0"
  done
  echo "jenkins out $SONARQUBE_HTTP_PORT sg:sonarqube"
  echo "jenkins out $NEXUS_HTTP_PORT sg:nexus"
  echo "jenkins out $NEXUS_DOCKER_PORT sg:nexus"
  for e in "${CG_ENVS[@]}"; do
    echo "jenkins out 22 sg:env-$e"
    echo "env-$e out $NEXUS_DOCKER_PORT sg:nexus"
  done
}

authorize() { # authorize <sg id> <in|out> <port> <peer>
  local perm
  if [[ "$4" == cidr:* ]]; then
    perm="IpProtocol=tcp,FromPort=$3,ToPort=$3,IpRanges=[{CidrIp=${4#cidr:},Description=cg-managed}]"
  else
    perm="IpProtocol=tcp,FromPort=$3,ToPort=$3,UserIdGroupPairs=[{GroupId=${4#sg:},Description=cg-managed}]"
  fi
  if [[ "$2" == in ]]; then
    aws_ ec2 authorize-security-group-ingress --group-id "$1" --ip-permissions "$perm" >/dev/null
  else
    aws_ ec2 authorize-security-group-egress --group-id "$1" --ip-permissions "$perm" >/dev/null
  fi
}

# reconcile_rules <sg key>: adds missing rules and revokes any rule that is not desired
# (including the default allow-all egress rule of new groups).
reconcile_rules() {
  local key=$1 name id k dir port peer rid egress proto from to cidr ref ok=0
  local -A want=() have=()
  name=$(cg_sg_name "$key")
  id=${SG_ID[$key]}
  while read -r k dir port peer; do
    [[ "$k" == "$key" ]] || continue
    if [[ "$peer" == sg:* ]]; then
      if ! is_real "${SG_ID[${peer#sg:}]}"; then
        want["$dir tcp $port $peer"]=1
        continue
      fi
      peer="sg:${SG_ID[${peer#sg:}]}"
    fi
    want["$dir tcp $port $peer"]=1
  done < <(desired_rules)
  if ! is_real "$id"; then
    planned "$name: aplicar ${#want[@]} reglas de mínimo privilegio"
    return
  fi
  while read -r rid egress proto from to cidr ref; do
    [[ -n "${rid:-}" ]] || continue
    dir=in
    [[ "$egress" == True ]] && dir=out
    if nz "$ref"; then peer="sg:$ref"; else peer="cidr:$cidr"; fi
    if [[ "$proto" == tcp && "$from" == "$to" ]]; then k="$dir tcp $from $peer"; else k="$dir $proto $from-$to $peer"; fi
    have["$k"]=$rid
  done < <(aws_ ec2 describe-security-group-rules --filters "Name=group-id,Values=$id" \
    --query 'SecurityGroupRules[].[SecurityGroupRuleId,IsEgress,IpProtocol,FromPort,ToPort,CidrIpv4,ReferencedGroupInfo.GroupId]' --output text)

  for k in "${!want[@]}"; do
    if [[ -n "${have[$k]:-}" ]]; then
      ok=$((ok + 1))
      continue
    fi
    read -r dir _ port peer <<<"$k"
    if is_apply && { [[ "$peer" == cidr:* ]] || is_real "${peer#sg:}"; }; then
      authorize "$id" "$dir" "$port" "$peer"
      updated "$name: permitido $dir tcp/$port $(cg_mask "$peer")"
    else
      planned "$name: permitir $dir tcp/$port $(cg_mask "$peer")"
    fi
  done
  for k in "${!have[@]}"; do
    [[ -n "${want[$k]:-}" ]] && continue
    read -r dir _ <<<"$k"
    if ! is_apply; then
      planned "$name: revocar la regla no deseada '$(cg_mask "$k")'"
      continue
    fi
    if [[ "$dir" == in ]]; then
      aws_ ec2 revoke-security-group-ingress --group-id "$id" --security-group-rule-ids "${have[$k]}" >/dev/null
    else
      aws_ ec2 revoke-security-group-egress --group-id "$id" --security-group-rule-ids "${have[$k]}" >/dev/null
    fi
    updated "$name: revocada la regla '$(cg_mask "$k")'"
  done
  ((ok > 0)) && unchanged "$name: $ok reglas conformes"
  return 0
}

cg_parse_flags "$@"
cg_load_config
cg_start_log bootstrap-network
cg_aws_preflight

ADMIN_LIST=$(cg_admin_cidrs)
mapfile -t ADMIN <<<"$ADMIN_LIST"
info "red $VPC_CIDR en $AWS_REGION/$AWS_AZ; acceso administrativo desde: $(cg_mask "${ADMIN[*]}")"

ensure_vpc
ensure_igw
ensure_subnet tools "$SUBNET_TOOLS_CIDR"
for env_name in "${CG_ENVS[@]}"; do ensure_subnet "$env_name" "$(cg_env_value "$env_name" ENV_SUBNET_CIDR)"; done
ensure_route_table
for key in "${SG_KEYS[@]}"; do ensure_sg "$key"; done
for key in "${SG_KEYS[@]}"; do reconcile_rules "$key"; done
cg_summary bootstrap-network
