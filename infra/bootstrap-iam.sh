#!/usr/bin/env bash
# HU-01 · IAM identities used by the other scripts, so that daily work never runs with
# administrative or permanent credentials (see bootstrap/lib/session.sh):
#   roles  circleguard-hu01-reader    read-only, prices and stopping instances
#          circleguard-hu01-operator  create and start resources, no deletes
#          circleguard-hu01-teardown  delete the tagged resources of HU-01
#   users  circleguard-hu01-operator  `aws login` on the workstation; may assume reader, and
#                                     operator only with an MFA code sent in AssumeRole
#          circleguard-hu01-teardown  console + AWS CloudShell only; may assume teardown only,
#                                     with an MFA code (< 15 min). Never used on the workstation
# The users get no access keys. Their console password and MFA device are set by the person in
# the AWS console; no script ever sees them.
#
# Runs with the bootstrap session (infra/aws-session.sh login bootstrap).
#   --plan (default)         read-only inspection of the account, Access Analyzer and the plan
#   --audit                  CloudTrail: MFA context of the session and write events since login
#   --apply --approve iam    creates or converges the IAM resources above (no cost)

# shellcheck source=bootstrap/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/aws.sh
source "$INFRA_DIR/bootstrap/lib/aws.sh"

usage() {
  cat <<'EOF'
Uso: infra/bootstrap-iam.sh [--plan | --audit | --apply --approve iam]
  --plan                 (por defecto) inspección de solo lectura de la cuenta, validación de las
                         políticas con Access Analyzer y plan de IAM. No cambia nada.
  --audit                CloudTrail: contexto MFA de la sesión y operaciones de escritura
                         realizadas desde el último 'aws-session.sh login bootstrap'.
  --apply --approve iam  crea o converge las políticas, roles y usuarios de HU-01 (sin costo).
Requiere la sesión bootstrap: bash infra/aws-session.sh login bootstrap
EOF
}

IAM_DIR="$INFRA_DIR/config/iam"
# Privilege escalation and account-level actions that no HU-01 identity may have.
ESCALATION=(iam:CreateAccessKey iam:CreateLoginProfile iam:UpdateLoginProfile iam:ChangePassword iam:PutUserPolicy
  iam:AttachUserPolicy iam:PutRolePolicy iam:AttachRolePolicy iam:UpdateAssumeRolePolicy iam:CreatePolicyVersion
  iam:SetDefaultPolicyVersion iam:DeleteRolePermissionsBoundary iam:PassRole iam:CreateRole iam:CreateUser
  iam:AddUserToGroup iam:DeactivateMFADevice iam:CreateServiceLinkedRole ssm:SendCommand ssm:StartSession
  lambda:CreateFunction cloudformation:CreateStack organizations:CreateOrganization freetier:UpgradeAccountPlan
  servicequotas:RequestServiceQuotaIncrease)
TAGS=('Key=Project,Value=circleguard' 'Key=Story,Value=HU-01' 'Key=ManagedBy,Value=infra-bootstrap')
# Every IAM action that --apply uses (also the minimum the bootstrap identity needs).
IAM_ACTIONS=(iam:GetPolicy iam:GetPolicyVersion iam:ListPolicyVersions iam:CreatePolicy iam:CreatePolicyVersion
  iam:TagPolicy iam:GetRole iam:CreateRole iam:TagRole iam:UpdateAssumeRolePolicy iam:UpdateRole
  iam:ListAttachedRolePolicies iam:AttachRolePolicy iam:GetUser iam:CreateUser iam:TagUser iam:GetUserPolicy
  iam:PutUserPolicy iam:ListAccessKeys iam:GetLoginProfile iam:ListMFADevices)

# try <aws args>: output of a read-only call, or "error: <code>" without stopping the run.
try() {
  local out code
  if out=$(aws "$@" 2>&1 </dev/null); then
    printf '%s' "$out"
    return 0
  fi
  code=$(grep -oE 'An error occurred \([^)]+\)' <<<"$out" | head -1 | sed -E 's/.*\((.*)\)/\1/' || true)
  printf 'error: %s' "${code:-$(head -c 160 <<<"${out%%$'\n'*}")}"
  return 1
}

# iam_lookup <aws iam args>: prints the result and succeeds when the entity exists, fails when
# it does not (NoSuchEntity) and stops on any other error (for example, missing permissions).
iam_lookup() {
  local out
  if out=$(aws iam "$@" 2>&1 </dev/null); then
    printf '%s' "$out"
    return 0
  fi
  [[ "$out" == *NoSuchEntity* ]] && return 1
  die "iam $1 falló: ${out%%$'\n'*}"
}

# render <template>: copy of an IAM template with the account id, in the private work dir.
render() {
  sed "s/<ACCOUNT_ID>/$ACCOUNT/g" "$IAM_DIR/$1" >"$WORK/$1"
  printf '%s' "$WORK/$1"
}

same_json() {
  python3 -c 'import json, sys; a, b = (json.load(open(p)) for p in sys.argv[1:]); sys.exit(json.dumps(a, sort_keys=True) != json.dumps(b, sort_keys=True))' "$1" "$2"
}

# ---------------------------------------------------------------------------------------
# Read-only inspection
# ---------------------------------------------------------------------------------------

inspect_identity() {
  case "$CG_AWS_ARN" in
    *:root) KIND=raiz ;;
    *:user/*) KIND=usuario-iam ;;
    *:assumed-role/AWSReservedSSO_*) KIND=identity-center ;;
    *:assumed-role/voclabs/* | *:assumed-role/vocstartsoft/* | *:assumed-role/*LabRole*) KIND=aws-academy ;;
    *:assumed-role/*) KIND=rol ;;
    *:federated-user/*) KIND=federada ;;
    *) KIND=otra ;;
  esac
  info "identidad: ${CG_AWS_ARN##*:} · tipo $KIND · cuenta ****${ACCOUNT: -4} · credenciales temporales (aws login)"
  if [[ "$KIND" == raiz ]]; then
    warn "es la cuenta raíz: se usa solo para esta inspección y, si se aprueba, para crear IAM; después se cierra la sesión"
    info "MFA de la cuenta raíz: $(try iam get-account-summary --query SummaryMap.AccountMFAEnabled --output text |
      sed 's/^1$/activado/; s/^0$/NO activado/' || true)"
  fi
  [[ "$KIND" == aws-academy ]] &&
    warn "parece AWS Academy (Learner Lab): normalmente no permite crear IAM y limita las regiones; el plan no es aplicable"
  return 0
}

inspect_organization() {
  local out
  if out=$(try organizations describe-organization --query Organization.MasterAccountId --output text); then
    if [[ "$out" == "$ACCOUNT" ]]; then ORG=administracion; else ORG=miembro; fi
  else
    case "$out" in *AWSOrganizationsNotInUseException*) ORG=independiente ;; *) ORG="desconocido ($out)" ;; esac
  fi
  info "organización: $ORG"
  [[ "$ORG" == miembro ]] &&
    warn "cuenta miembro de una organización: sus SCP pueden limitar IAM, regiones o tipos y no se pueden leer desde aquí"
  return 0
}

inspect_account_plan() {
  local out
  if out=$(try freetier get-account-plan-state --region us-east-1 --output json); then
    PLAN_TYPE=$(python3 -c 'import json, sys; print(json.load(sys.stdin).get("accountPlanType", "?"))' <<<"$out")
    python3 -c '
import json, sys
d = json.load(sys.stdin)
c = d.get("accountPlanRemainingCredits") or {}
values = (d.get("accountPlanType", "?"), d.get("accountPlanStatus", "?"), c.get("amount", "?"), c.get("unit", ""), d.get("accountPlanExpirationDate", "-"))
print("  plan %s · estado %s · créditos del plan restantes %s %s · vence %s" % values)' <<<"$out" >&2
  else
    PLAN_TYPE="?"
    info "plan de la cuenta: no disponible ($out); revise Billing > Créditos en la consola"
  fi
  [[ "$PLAN_TYPE" == FREE ]] &&
    warn "plan gratuito: AWS solo admite en él tipos aptos para la capa gratuita; cambiar de plan es una decisión suya (no se hace aquí)"
  return 0
}

inspect_region_zone() {
  local out types t vcpus need=0 quota
  info "región $AWS_REGION: $(try account get-region-opt-status --region-name "$AWS_REGION" --query RegionOptStatus --output text || true)"
  info "zona $AWS_AZ: $(try ec2 describe-availability-zones --region "$AWS_REGION" --zone-names "$AWS_AZ" --query 'AvailabilityZones[0].State' --output text || true)"
  local ami ami_arch ami_ena ami_boot free cpus mib archs boots ena verdict
  ami=$(try ssm get-parameter --region "$AWS_REGION" --name "$AMI_SSM_PARAM" --query Parameter.Value --output text) || true
  read -r ami_arch ami_ena ami_boot <<<"$(try ec2 describe-images --region "$AWS_REGION" --image-ids "$ami" \
    --query 'Images[0].[Architecture,EnaSupport,BootMode]' --output text || true)"
  info "AMI Ubuntu 24.04 vigente: $ami · arquitectura $ami_arch · ENA $ami_ena · arranque $ami_boot"
  types=$(for r in "${CG_ROLES[@]}"; do cg_role_type "$r"; echo; done | sort -u | sed '/^$/d')
  for t in $types; do
    out=$(try ec2 describe-instance-type-offerings --region "$AWS_REGION" --location-type availability-zone \
      --filters "Name=location,Values=$AWS_AZ" "Name=instance-type,Values=$t" --query 'InstanceTypeOfferings[0].InstanceType' --output text || true)
    [[ "$out" == "$t" ]] && out="ofrecido" || out="NO ofrecido ($out)"
    read -r free cpus mib archs boots ena <<<"$(try ec2 describe-instance-types --region "$AWS_REGION" --instance-types "$t" \
      --query 'InstanceTypes[0].[FreeTierEligible,VCpuInfo.DefaultVCpus,MemoryInfo.SizeInMiB,join(`,`,ProcessorInfo.SupportedArchitectures),join(`,`,SupportedBootModes),NetworkInfo.EnaSupport]' \
      --output text || true)"
    if [[ ",$archs," == *",$ami_arch,"* && ("$ena" != required || "$ami_ena" == True) ]]; then verdict=compatible; else verdict=INCOMPATIBLE; fi
    info "  $t en $AWS_AZ: $out · apto capa gratuita $free · $cpus vCPU · $mib MiB · $archs · arranque $boots · ENA $ena · AMI $verdict"
  done
  for r in "${CG_ROLES[@]}"; do
    vcpus=$(try ec2 describe-instance-types --region "$AWS_REGION" --instance-types "$(cg_role_type "$r")" \
      --query 'InstanceTypes[0].VCpuInfo.DefaultVCpus' --output text) || vcpus=2
    need=$((need + vcpus))
  done
  quota=$(try service-quotas get-service-quota --region "$AWS_REGION" --service-code ec2 --quota-code L-1216C47A \
    --query Quota.Value --output text) || true
  info "cuota vCPU On-Demand estándar en $AWS_REGION: ${quota} · necesarias con las 6 encendidas: $need"
  if [[ "$quota" =~ ^[0-9.]+$ ]] && awk -v q="$quota" -v n="$need" 'BEGIN { exit !(q < n) }'; then
    warn "la cuota de vCPU es menor que la necesaria: pedir un aumento es una decisión suya (Service Quotas)"
  fi
  return 0
}

inspect_identity_center() {
  local region
  for region in us-east-1 "$AWS_REGION"; do
    info "IAM Identity Center en $region: $(try sso-admin list-instances --region "$region" --query 'length(Instances)' --output text || true) instancia(s)"
  done
}

inspect_resources() {
  info "recursos circleguard existentes: instancias $(try ec2 describe-instances --region "$AWS_REGION" --filters Name=tag:Project,Values=circleguard \
    --query 'length(Reservations[].Instances[])' --output text || true) · VPC $(try ec2 describe-vpcs --region "$AWS_REGION" \
    --filters Name=tag:Project,Values=circleguard --query 'length(Vpcs)' --output text || true) · volúmenes $(try ec2 describe-volumes \
    --region "$AWS_REGION" --filters Name=tag:Project,Values=circleguard --query 'length(Volumes)' --output text || true) · secretos SSM $(try ssm \
    get-parameters-by-path --region "$AWS_REGION" --path /circleguard --recursive --query 'length(Parameters)' --output text || true)"
}

# inspect_iam_capability: can this identity create the IAM resources of the plan? Read-only.
inspect_iam_capability() {
  local src out denied
  case "$KIND" in
    raiz)
      info "permisos IAM: la cuenta raíz puede crearlos salvo que una SCP lo impida (organización: $ORG)"
      IAM_OK=true
      return
      ;;
    usuario-iam) src=$CG_AWS_ARN ;;
    identity-center | rol | aws-academy)
      local role=${CG_AWS_ARN#*:assumed-role/}
      src=$(try iam get-role --role-name "${role%%/*}" --query Role.Arn --output text) || {
        info "permisos IAM: no determinables ($src)"
        IAM_OK=unknown
        return
      }
      ;;
    *)
      info "permisos IAM: no determinables para el tipo $KIND"
      IAM_OK=unknown
      return
      ;;
  esac
  if out=$(try iam simulate-principal-policy --policy-source-arn "$src" --action-names "${IAM_ACTIONS[@]}" \
    --query 'EvaluationResults[].[EvalActionName,EvalDecision]' --output text); then
    denied=$(awk '$2 != "allowed" { print $1 }' <<<"$out" | tr '\n' ' ')
    if [[ -z "$denied" ]]; then
      IAM_OK=true
      info "permisos IAM: las ${#IAM_ACTIONS[@]} acciones del plan están permitidas (simulador IAM; las SCP se evalúan aparte)"
    else
      IAM_OK=false
      warn "permisos IAM: denegadas $denied: esta identidad no puede crear la infraestructura IAM"
    fi
  else
    IAM_OK=unknown
    info "permisos IAM: no determinables ($out)"
  fi
}

# validate_policies: Access Analyzer over every template, with the account id filled in.
validate_policies() {
  local f kind out errors=0
  for f in "$IAM_DIR"/hu01-*.json; do
    f=${f##*/}
    if [[ "$f" == *-trust.json ]]; then
      kind=(--policy-type RESOURCE_POLICY --validate-policy-resource-type AWS::IAM::AssumeRolePolicyDocument)
    else
      kind=(--policy-type IDENTITY_POLICY)
    fi
    out=$(aws accessanalyzer validate-policy --region "$AWS_REGION" "${kind[@]}" --policy-document "file://$(render "$f")" \
      --query 'findings[].[findingType,issueCode]' --output text </dev/null) || die "Access Analyzer no pudo validar $f"
    if [[ -z "$out" ]]; then
      info "  Access Analyzer $f: sin hallazgos"
    else
      info "  Access Analyzer $f: $(tr '\t\n' ': ' <<<"$out")"
      grep -qE '^(ERROR|SECURITY_WARNING)' <<<"$out" && errors=$((errors + 1))
    fi
  done
  ((errors == 0)) || die "Access Analyzer encontró errores o advertencias de seguridad en $errors plantilla(s): no se aplica nada."
}

# check_escalation: IAM policy simulator (free, read-only) over the templates: no HU-01 identity
# may change permissions, create credentials, pass roles, change the account or reach the
# teardown role; and only the teardown user is trusted by the teardown role.
check_escalation() {
  local who f out allowed fail=0 teardown="arn:aws:iam::$ACCOUNT:role/circleguard-hu01-teardown"
  local -A sets=([usuario-operador]="hu01-operator-user-policy.json" [rol-lectura]="hu01-reader-policy.json"
    [rol-operador]="hu01-operator-policy.json" [usuario-teardown]="hu01-teardown-user-policy.json"
    [rol-teardown]="hu01-reader-policy.json hu01-teardown-policy.json")
  for who in usuario-operador rol-lectura rol-operador usuario-teardown rol-teardown; do
    local docs=()
    for f in ${sets[$who]}; do docs+=("$(cat "$(render "$f")")"); done
    allowed=$(aws iam simulate-custom-policy --policy-input-list "${docs[@]}" --action-names "${ESCALATION[@]}" \
      --resource-arns '*' --query 'EvaluationResults[?EvalDecision==`allowed`].EvalActionName' --output text </dev/null) ||
      die "No se pudo ejecutar el simulador de políticas IAM."
    if [[ "$who" != usuario-teardown ]]; then
      out=$(aws iam simulate-custom-policy --policy-input-list "${docs[@]}" --action-names sts:AssumeRole \
        --resource-arns "$teardown" --query 'EvaluationResults[?EvalDecision==`allowed`].EvalActionName' --output text </dev/null)
      [[ -n "$out" ]] && allowed+=" sts:AssumeRole(teardown)"
    fi
    if [[ -z "${allowed// /}" ]]; then
      info "  simulador IAM $who: ninguna acción de escalada permitida (${#ESCALATION[@]} acciones y asumir teardown)"
    else
      warn "  simulador IAM $who: PERMITIDO $allowed"
      fail=1
    fi
  done
  out=$(python3 -c 'import json, sys; print(" ".join(json.load(open(sys.argv[1]))["Statement"][0]["Principal"]["AWS"].split()))' \
    "$(render hu01-teardown-role-trust.json)")
  if [[ "$out" == "arn:aws:iam::$ACCOUNT:user/circleguard-hu01-teardown" ]]; then
    info "  confianza del rol teardown: solo el usuario circleguard-hu01-teardown, con MFA de menos de 15 min"
  else
    warn "  confianza del rol teardown inesperada: $out"
    fail=1
  fi
  ((fail == 0)) || die "La revisión de escalada de privilegios falló: no se aplica nada."
}

# trail <region> <attribute key> <value>: CloudTrail events of this identity since the bootstrap
# login, one per line: time source name readOnly mfaAuthenticated error.
trail() {
  aws cloudtrail lookup-events --region "$1" --start-time "$SINCE" --lookup-attributes "AttributeKey=$2,AttributeValue=$3" \
    --max-items 200 --output json </dev/null | python3 -c '
import json, sys
arn = sys.argv[1]
for e in json.load(sys.stdin).get("Events", []):
    ct = json.loads(e["CloudTrailEvent"])
    who = ct.get("userIdentity", {})
    if who.get("arn") != arn:
        continue
    mfa = who.get("sessionContext", {}).get("attributes", {}).get("mfaAuthenticated", "-")
    print(ct["eventTime"], ct["eventSource"], ct["eventName"], ct.get("readOnly"), mfa, ct.get("errorCode", "-"))' "$CG_AWS_ARN"
}

audit_cloudtrail() {
  local mfa writes region line
  info "CloudTrail desde $SINCE (los eventos tardan hasta 15 min en aparecer):"
  mfa=$(trail "$AWS_REGION" EventName DescribeAvailabilityZones | awk '{ print $5 }' | sort | uniq -c | tr '\n' ' ') || true
  info "  contexto MFA de esta sesión (mfaAuthenticated): ${mfa:-sin eventos todavía}"
  for region in us-east-1 "$AWS_REGION"; do
    writes=$(trail "$region" ReadOnly false) || writes="no disponible (sin permiso cloudtrail:LookupEvents)"
    if [[ -z "$writes" ]]; then
      info "  operaciones de escritura en $region: ninguna"
    else
      info "  operaciones de escritura en $region:"
      while read -r line; do info "    $line"; done <<<"$writes"
    fi
  done
}

# ---------------------------------------------------------------------------------------
# Plan / apply (IAM has no cost)
# ---------------------------------------------------------------------------------------

ensure_policy() {
  local name="circleguard-hu01-$1" arn doc version
  arn="arn:aws:iam::$ACCOUNT:policy/circleguard-hu01-$1"
  doc=$(render "hu01-$1-policy.json")
  if version=$(iam_lookup get-policy --policy-arn "$arn" --query Policy.DefaultVersionId --output text); then
    aws iam get-policy-version --policy-arn "$arn" --version-id "$version" --query PolicyVersion.Document --output json >"$WORK/current.json"
    if same_json "$doc" "$WORK/current.json"; then
      unchanged "política $name"
    elif is_apply; then
      (($(aws iam list-policy-versions --policy-arn "$arn" --query 'length(Versions)' --output text) < 5)) ||
        die "La política $name ya tiene 5 versiones: elimine una antigua manualmente (no se borra nada automáticamente)."
      aws iam create-policy-version --policy-arn "$arn" --policy-document "file://$doc" --set-as-default >/dev/null
      updated "política $name (nueva versión por defecto)"
    else
      planned "actualizar la política $name con una nueva versión"
    fi
  elif is_apply; then
    aws iam create-policy --policy-name "$name" --policy-document "file://$doc" --tags "${TAGS[@]}" \
      --description "CircleGuard HU-01 ($1)" >/dev/null
    created "política administrada $name"
  else
    planned "crear la política administrada $name"
  fi
}

ensure_role() { # ensure_role <name> <trust template> <policy>...
  local name="circleguard-hu01-$1" trust p attached exists=true
  trust=$(render "$2")
  shift 2
  if iam_lookup get-role --role-name "$name" --query Role.AssumeRolePolicyDocument --output json >"$WORK/trust.json"; then
    if same_json "$trust" "$WORK/trust.json"; then
      unchanged "confianza del rol $name"
    elif is_apply; then
      aws iam update-assume-role-policy --role-name "$name" --policy-document "file://$trust"
      updated "confianza del rol $name"
    else
      planned "actualizar la confianza del rol $name"
    fi
    if [[ "$(aws iam get-role --role-name "$name" --query Role.MaxSessionDuration --output text)" == 3600 ]]; then
      unchanged "rol $name: sesiones de 1 h como máximo"
    elif is_apply; then
      aws iam update-role --role-name "$name" --max-session-duration 3600
      updated "rol $name: sesiones de 1 h como máximo"
    else
      planned "limitar las sesiones del rol $name a 1 h"
    fi
  elif is_apply; then
    aws iam create-role --role-name "$name" --assume-role-policy-document "file://$trust" --max-session-duration 3600 \
      --tags "${TAGS[@]}" --description "CircleGuard HU-01 $name" >/dev/null
    created "rol $name (sesiones de 1 h como máximo)"
  else
    planned "crear el rol $name (confianza ${trust##*/}, sesiones de 1 h como máximo)"
    exists=false
  fi
  attached=""
  if $exists || is_apply; then
    attached=$(aws iam list-attached-role-policies --role-name "$name" --query 'AttachedPolicies[].PolicyName' --output text)
  fi
  for p in "$@"; do
    if [[ " $attached " == *" circleguard-hu01-$p "* ]]; then
      unchanged "rol $name: política circleguard-hu01-$p adjunta"
    elif is_apply; then
      aws iam attach-role-policy --role-name "$name" --policy-arn "arn:aws:iam::$ACCOUNT:policy/circleguard-hu01-$p"
      updated "rol $name: política circleguard-hu01-$p adjuntada"
    else
      planned "adjuntar circleguard-hu01-$p al rol $name"
    fi
  done
}

ensure_user() { # ensure_user <name> <inline policy template>
  local name="circleguard-hu01-$1" doc keys
  doc=$(render "$2")
  if iam_lookup get-user --user-name "$name" >/dev/null; then
    unchanged "usuario $name"
  elif is_apply; then
    aws iam create-user --user-name "$name" --tags "${TAGS[@]}" >/dev/null
    created "usuario $name (sin claves de acceso ni contraseña)"
  else
    planned "crear el usuario $name sin claves de acceso ni contraseña"
    planned "política en línea $name-access desde $2"
    return 0
  fi
  if iam_lookup get-user-policy --user-name "$name" --policy-name "$name-access" --query PolicyDocument --output json >"$WORK/inline.json" &&
    same_json "$doc" "$WORK/inline.json"; then
    unchanged "usuario $name: política en línea $name-access"
  elif is_apply; then
    aws iam put-user-policy --user-name "$name" --policy-name "$name-access" --policy-document "file://$doc"
    updated "usuario $name: política en línea $name-access"
  else
    planned "aplicar la política en línea $name-access al usuario $name"
  fi
  keys=$(aws iam list-access-keys --user-name "$name" --query 'length(AccessKeyMetadata)' --output text)
  ((keys == 0)) || warn "el usuario $name tiene $keys clave(s) de acceso: HU-01 no las usa; desactívelas en la consola"
  if iam_lookup get-login-profile --user-name "$name" >/dev/null; then
    info "usuario $name: contraseña de consola definida"
  else
    info "usuario $name: contraseña de consola PENDIENTE (la define usted en la consola de AWS)"
  fi
  info "usuario $name: dispositivos MFA $(aws iam list-mfa-devices --user-name "$name" --query 'length(MFADevices)' --output text)"
}

ensure_profiles() {
  local base="arn:aws:iam::$ACCOUNT:role/circleguard-hu01"
  if ! is_apply; then
    planned "añadir los perfiles locales circleguard-hu01-reader y circleguard-hu01 (teardown solo existe en CloudShell)"
    return
  fi
  cg_aws_profile_ensure circleguard-hu01-reader "role_arn = $base-reader" "source_profile = circleguard-hu01-operator-login" \
    "duration_seconds = 3600" "region = $AWS_REGION"
  cg_aws_profile_ensure circleguard-hu01 "role_arn = $base-operator" "source_profile = circleguard-hu01-operator-login" \
    "duration_seconds = 3600" "region = $AWS_REGION"
}

cg_parse_flags "$@"
cg_load_config
AUDIT=false
for arg in "${CG_ARGS[@]}"; do
  case "$arg" in
    --audit) AUDIT=true ;;
    *) die "opción desconocida: $arg" ;;
  esac
done
if is_apply && [[ ",$CG_APPROVED," != *",iam,"* ]]; then
  die "Crear la infraestructura IAM requiere --apply --approve iam."
fi
cg_start_log bootstrap-iam
cg_aws_use bootstrap
cg_aws_identity
ACCOUNT=$(cut -d: -f5 <<<"$CG_AWS_ARN")
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
SINCE=$(cat "$CG_AWS_HOME/login-bootstrap.started" 2>/dev/null || date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ)

if $AUDIT; then
  audit_cloudtrail
  exit 0
fi
inspect_identity
inspect_organization
inspect_account_plan
inspect_region_zone
inspect_identity_center
inspect_resources
inspect_iam_capability
validate_policies
check_escalation
if is_apply; then
  [[ "$KIND" != aws-academy ]] || die "AWS Academy no permite crear esta infraestructura IAM."
  [[ "$IAM_OK" != false ]] || die "Esta identidad no tiene los permisos IAM necesarios."
fi
for p in reader operator teardown; do ensure_policy "$p"; done
ensure_role reader hu01-reader-role-trust.json reader
ensure_role operator hu01-operator-role-trust.json operator
ensure_role teardown hu01-teardown-role-trust.json reader teardown
ensure_user operator hu01-operator-user-policy.json
ensure_user teardown hu01-teardown-user-policy.json
ensure_profiles
info "pasos en la consola de AWS tras crear IAM (contraseña y MFA los escribe usted, nunca un script): ver infra/README.md, 'Primer acceso de los usuarios'"
cg_summary bootstrap-iam
