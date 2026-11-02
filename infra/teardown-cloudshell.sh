#!/usr/bin/env bash
# HU-01 · Destruction from AWS CloudShell, in the browser, signed in to the console as the IAM user
# circleguard-hu01-teardown. The teardown credentials never reach the operator's workstation:
# CloudShell takes the user's credentials from the console session, and the MFA code for the
# teardown role is typed here, into the AWS CLI's own prompt. Runs infra/teardown.sh --destroy:
# --plan by default; --apply also asks for the confirmation phrase.
#   bash infra/teardown-cloudshell.sh [--purge-secrets] [--apply]

# shellcheck source=bootstrap/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/aws.sh
source "$INFRA_DIR/bootstrap/lib/aws.sh"

usage() {
  cat <<'EOF'
Uso (en AWS CloudShell, como circleguard-hu01-teardown):
  bash infra/teardown-cloudshell.sh                     inventario y plan de destrucción, sin cambios
  bash infra/teardown-cloudshell.sh --apply             destruye (pide la frase de confirmación)
  bash infra/teardown-cloudshell.sh --purge-secrets --apply   además borra /circleguard/* de SSM
EOF
}

[[ "${1:-}" == -h || "${1:-}" == --help ]] && { usage; exit 0; }
cg_load_config
[[ "${AWS_EXECUTION_ENV:-}" == CloudShell ]] ||
  die "Este script solo se ejecuta en AWS CloudShell: la destrucción no se hace desde la estación de trabajo."
arn=$(aws sts get-caller-identity --query Arn --output text </dev/null)
[[ "$arn" == *":user/circleguard-hu01-teardown" ]] ||
  die "Inicie sesión en la consola como circleguard-hu01-teardown (identidad actual: ${arn##*:})."
account=$(cut -d: -f5 <<<"$arn")
serial=$(aws iam list-mfa-devices --query 'MFADevices[0].SerialNumber' --output text </dev/null)
[[ "$serial" == arn:aws:iam::* ]] || die "El usuario circleguard-hu01-teardown no tiene MFA asignado."

# The role profile takes the console credentials of CloudShell (container endpoint) and asks the
# AWS CLI to prompt for the MFA code once per run. Its session lasts 30 minutes: the AWS CLI
# treats cached role credentials with less than 15 minutes left as expired, so with 15-minute
# sessions every `aws` call assumed the role again and asked for another code. Profiles created
# with 900 seconds by earlier versions are updated.
cg_aws_profile_ensure circleguard-hu01-teardown "role_arn = arn:aws:iam::$account:role/circleguard-hu01-teardown" \
  "credential_source = EcsContainer" "mfa_serial = $serial" "duration_seconds = 1800" "region = $AWS_REGION"
old=$(aws configure get duration_seconds --profile circleguard-hu01-teardown </dev/null || true)
if [[ "$old" != 1800 ]]; then
  cg_aws_profile_unset circleguard-hu01-teardown duration_seconds
  cg_aws_profile_setting circleguard-hu01-teardown duration_seconds 1800
  updated "perfil circleguard-hu01-teardown: duration_seconds ${old:-sin valor} -> 1800"
fi
trap 'rm -f "$CG_AWS_HOME/.aws/cli/cache/"*.json' EXIT
info "escriba el código MFA de circleguard-hu01-teardown cuando la AWS CLI lo pida:"
role=$(aws sts get-caller-identity --profile circleguard-hu01-teardown --query Arn --output text) ||
  die "No se pudo asumir el rol de teardown (código MFA incorrecto o vencido)."
[[ "$role" == *":assumed-role/circleguard-hu01-teardown/"* ]] || die "Identidad inesperada tras asumir el rol: ${role##*:}."
# `aws configure list` and ~/.aws/config show CloudShell's own credentials (the user); this
# script keeps its profile under ~/.circleguard/aws.
info "rol asumido con MFA: ${role##*:} (perfil en ${CG_AWS_CONFIG/#$HOME/\~})"
CG_AWS_PROFILE=circleguard-hu01-teardown bash "$INFRA_DIR/teardown.sh" --destroy "$@"
