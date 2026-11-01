#!/usr/bin/env bash
# AWS CLI sessions of HU-01: only temporary credentials, one identity per capability.
# Requires common.sh to be sourced first.
#
# Everything the AWS CLI keeps for HU-01 (profiles, the `aws login` sessions and the cache of
# assumed-role credentials) lives under ~/.circleguard/aws on the WSL file system with mode
# 0700, never in ~/.aws: on the team workstation ~/.aws points to an NTFS folder where chmod
# has no effect. Access keys are neither created nor accepted.
#
# Capability -> profile -> identity
#   bootstrap  circleguard-hu01-bootstrap  the account's existing identity (aws login); only for
#                                          the read-only inspection and bootstrap-iam.sh
#   read       circleguard-hu01-reader     role reader: describe, prices, stop instances
#   operate    circleguard-hu01            role operator: create and start, no deletes; assumed
#                                          with a one-time MFA code, sessions of 1 h at most
#   destroy    circleguard-hu01-teardown   role teardown: delete tagged resources. Only the
#                                          teardown user can assume it, with an MFA code, and
#                                          only from AWS CloudShell (infra/teardown-cloudshell.sh):
#                                          its credentials never exist on the workstation
# The reader and operator roles take their credentials from the sign-in session
# circleguard-hu01-operator-login (`infra/aws-session.sh login operator`). An `aws login` session
# carries no MFA context (verified in CloudTrail on 2026-11-01), so the MFA condition of the
# operator role is met only by the code sent in AssumeRole (`infra/aws-session.sh unlock`).

CG_AWS_HOME="${CG_AWS_HOME:-$CG_LOCAL_HOME/aws}"
CG_AWS_CONFIG="$CG_AWS_HOME/.aws/config"
CG_CAPABILITY="${CG_CAPABILITY:-}"

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) if [[ -d "$HOME/.local/bin" ]]; then PATH="$HOME/.local/bin:$PATH"; fi ;;
esac

# Environment of every AWS CLI call: the protected directory as its home, and no fallback to
# instance-metadata credentials. Wrappers that exec the binary themselves (timeout, env) must
# pass it explicitly: `timeout 60 env "${CG_AWS_ENV[@]}" aws ...`.
CG_AWS_ENV=("HOME=$CG_AWS_HOME" "AWS_CONFIG_FILE=$CG_AWS_CONFIG" "AWS_SHARED_CREDENTIALS_FILE=$CG_AWS_HOME/.aws/credentials"
  "AWS_LOGIN_CACHE_DIRECTORY=$CG_AWS_HOME/.aws/login/cache" "AWS_EC2_METADATA_DISABLED=true")
aws() { env "${CG_AWS_ENV[@]}" aws "$@"; }

# cg_login_profile <bootstrap|operator>: profile of an `aws login` session.
cg_login_profile() {
  case "$1" in
    bootstrap) echo circleguard-hu01-bootstrap ;;
    operator) echo circleguard-hu01-operator-login ;;
    *) die "Sesión desconocida '$1' (use bootstrap u operator; la destrucción se hace en AWS CloudShell)" ;;
  esac
}

# cg_aws_use <bootstrap|read|operate|destroy>: profile of the capability the run needs.
# CG_AWS_PROFILE overrides it; the identity check of cg_aws_identity still applies.
cg_aws_use() {
  CG_CAPABILITY=$1
  case "$1" in
    bootstrap) AWS_PROFILE=circleguard-hu01-bootstrap ;;
    read) AWS_PROFILE=circleguard-hu01-reader ;;
    operate) AWS_PROFILE=circleguard-hu01 ;;
    destroy) AWS_PROFILE=circleguard-hu01-teardown ;;
    *) die "Capacidad desconocida: $1" ;;
  esac
  AWS_PROFILE=${CG_AWS_PROFILE:-$AWS_PROFILE}
  export AWS_PROFILE
}

cg_session_hint() {
  case "$CG_CAPABILITY" in
    bootstrap) echo "inicie sesión con la identidad actual de la cuenta: bash infra/aws-session.sh login bootstrap" ;;
    read) echo "inicie sesión como operador: bash infra/aws-session.sh login operator" ;;
    operate) echo "el rol de operación exige un código MFA nuevo (sesiones de 1 h): bash infra/aws-session.sh unlock" ;;
    destroy) echo "la destrucción se ejecuta en AWS CloudShell con el usuario de teardown: bash infra/aws-session.sh cloudshell-bundle" ;;
  esac
}

# cg_aws_identity: validates, without prompting, that AWS_PROFILE yields temporary credentials
# of the identity that matches CG_CAPABILITY. Sets CG_AWS_ARN.
cg_aws_identity() {
  local expected
  type -P aws >/dev/null || die "Falta AWS CLI v2 (se espera en ~/.local/bin/aws)."
  [[ -z "${AWS_ACCESS_KEY_ID:-}" ]] ||
    die "Hay claves AWS en variables de entorno: HU-01 solo usa credenciales temporales (infra/aws-session.sh)."
  [[ ! -s "$CG_AWS_HOME/.aws/credentials" ]] ||
    die "Existe un archivo de claves permanentes en $CG_AWS_HOME/.aws/credentials: HU-01 no las admite."
  if grep -qiE '^[[:space:]]*aws_(access_key_id|secret_access_key)[[:space:]]*=' "$CG_AWS_CONFIG" 2>/dev/null; then
    die "$CG_AWS_CONFIG contiene claves permanentes: HU-01 no las admite."
  fi
  CG_AWS_ARN=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null </dev/null) ||
    die "No hay una sesión AWS válida para el perfil $AWS_PROFILE: $(cg_session_hint). Ver infra/README.md."
  case "$CG_CAPABILITY" in
    bootstrap) expected='^arn:aws:(iam|sts)::' ;;
    read) expected=':assumed-role/circleguard-hu01-(reader|operator|teardown)/' ;;
    operate) expected=':assumed-role/circleguard-hu01-operator/' ;;
    destroy) expected=':assumed-role/circleguard-hu01-teardown/' ;;
  esac
  [[ "$CG_AWS_ARN" =~ $expected ]] ||
    die "La identidad '${CG_AWS_ARN##*:}' no corresponde a la capacidad '$CG_CAPABILITY': $(cg_session_hint)."
}

# cg_aws_profile_ensure <name> <line>...: appends a profile to the HU-01 configuration when it
# is missing. Existing profiles are never rewritten.
cg_aws_profile_ensure() {
  local name=$1
  shift
  install -d -m 700 "$CG_AWS_HOME" "$CG_AWS_HOME/.aws"
  [[ -e "$CG_AWS_CONFIG" ]] || (umask 077 && : >"$CG_AWS_CONFIG")
  chmod 600 "$CG_AWS_CONFIG"
  if grep -qxF "[profile $name]" "$CG_AWS_CONFIG"; then
    unchanged "perfil $name"
    return 0
  fi
  printf '\n[profile %s]\n' "$name" >>"$CG_AWS_CONFIG"
  printf '%s\n' "$@" >>"$CG_AWS_CONFIG"
  created "perfil $name en ${CG_AWS_CONFIG/#$HOME/\~}"
}

# cg_aws_profile_setting <profile> <key> <value>: adds a setting to an existing profile when the
# key is missing; a value that is already there is never rewritten.
cg_aws_profile_setting() {
  python3 - "$CG_AWS_CONFIG" "$@" <<'PY'
import sys
path, profile, key, value = sys.argv[1:]
lines = open(path).read().splitlines()
start = lines.index(f'[profile {profile}]')
end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith('[')), len(lines))
if not any(line.split('=')[0].strip() == key for line in lines[start + 1:end]):
    lines.insert(start + 1, f'{key} = {value}')
    open(path, 'w').write('\n'.join(lines) + '\n')
PY
}
