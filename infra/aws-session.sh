#!/usr/bin/env bash
# HU-01 · AWS sessions without permanent keys. `login` opens the official AWS sign-in page in the
# Windows browser (`aws login`): user names, passwords and MFA codes are typed ONLY there. The
# AWS CLI receives temporary credentials and renews them by itself while the console session
# lasts. `unlock` opens a terminal window where the person types the operator's MFA code into
# the AWS CLI's own prompt; the operator role session lasts 1 h at most. Destruction never runs
# here: `cloudshell-bundle` prepares the files for AWS CloudShell (infra/teardown-cloudshell.sh).
# Profiles and caches live in ~/.circleguard/aws (0700). This script changes nothing in AWS.

# shellcheck source=bootstrap/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/aws.sh
source "$INFRA_DIR/bootstrap/lib/aws.sh"

usage() {
  cat <<'EOF'
Uso: infra/aws-session.sh <comando>
  init                       crea ~/.circleguard/aws (0700) y los perfiles de inicio de sesión
  login bootstrap|operator   abre la página oficial de AWS: usuario, contraseña y MFA se escriben
                             solo allí
  unlock                     abre una ventana donde usted escribe el código MFA del operador en
                             la AWS CLI; habilita el rol de operación durante 1 h como máximo
  status                     sesiones activas (nunca muestra credenciales)
  logout bootstrap|operator|all
                             borra la sesión local y las credenciales de rol derivadas
  cloudshell-bundle          prepara el paquete para destruir desde AWS CloudShell
Sesiones:
  bootstrap  la identidad que ya usa en la cuenta: inspección de solo lectura y bootstrap-iam.sh
  operator   usuario IAM circleguard-hu01-operator: rol de lectura y, con unlock, rol de operación
EOF
}

UNLOCK_MARK="$CG_AWS_HOME/unlock.done"

init_home() {
  local kind
  for kind in bootstrap operator; do
    cg_aws_profile_ensure "$(cg_login_profile "$kind")" "region = $AWS_REGION"
  done
  info "configuración AWS de HU-01: ${CG_AWS_CONFIG/#$HOME/\~} (permisos $(stat -c %a "$CG_AWS_HOME"))"
}

show_identity() { # show_identity <profile>: state of a session, without credentials
  local arn account
  if arn=$(aws sts get-caller-identity --profile "$1" --query Arn --output text 2>/dev/null </dev/null); then
    account=$(cut -d: -f5 <<<"$arn")
    printf '  %-32s activa    %s · cuenta ****%s\n' "$1" "${arn##*:}" "${account: -4}" >&2
  else
    printf '  %-32s inactiva\n' "$1" >&2
  fi
}

do_login() {
  local profile
  profile=$(cg_login_profile "$1")
  grep -qxF "[profile $profile]" "$CG_AWS_CONFIG" 2>/dev/null || die "Ejecute primero: bash infra/aws-session.sh init"
  info "se abre la página oficial de AWS en su navegador: escriba allí su usuario, contraseña y código MFA."
  info "nunca los escriba en el chat. Esperando a que termine el inicio de sesión (máx. 15 min)..."
  date -u +%Y-%m-%dT%H:%M:%SZ >"$CG_AWS_HOME/login-$1.started"
  BROWSER="$CG_LIB_DIR/open-aws-url.sh" timeout 900 env "${CG_AWS_ENV[@]}" aws login --profile "$profile" </dev/null >&2 ||
    die "No se completó el inicio de sesión (cancelado o caducado). Puede repetirlo."
  show_identity "$profile"
}

# do_unlock: the operator role requires an MFA code in AssumeRole. The code is typed by the
# person into the AWS CLI prompt of a separate terminal window; this process only waits for the
# window to finish and never reads the code.
do_unlock() {
  local serial
  grep -qxF "[profile circleguard-hu01]" "$CG_AWS_CONFIG" 2>/dev/null ||
    die "Falta el perfil del rol de operación: se crea con bootstrap-iam.sh --apply --approve iam."
  serial=$(aws iam list-mfa-devices --profile "$(cg_login_profile operator)" --query 'MFADevices[0].SerialNumber' \
    --output text 2>/dev/null </dev/null) || die "Inicie primero la sesión del operador: bash infra/aws-session.sh login operator"
  [[ "$serial" == arn:aws:iam::* ]] || die "El usuario circleguard-hu01-operator no tiene MFA asignado (ver infra/README.md)."
  cg_aws_profile_setting circleguard-hu01 mfa_serial "$serial"
  rm -f "$UNLOCK_MARK"
  info "se abre una ventana de terminal: escriba allí el código MFA del operador cuando la AWS CLI lo pida."
  powershell.exe -NoProfile -NonInteractive -Command \
    "Start-Process wt.exe -ArgumentList 'wsl.exe','-d','${WSL_DISTRO_NAME:?solo en WSL}','--cd','$REPO_DIR','--','bash','infra/aws-session.sh','mfa-prompt'" >/dev/null
  timeout 300 bash -c "until [[ -e '$UNLOCK_MARK' ]]; do sleep 2; done" ||
    die "No se completó el desbloqueo en 5 minutos. Puede repetirlo."
  rm -f "$UNLOCK_MARK"
  CG_CAPABILITY=operate AWS_PROFILE=circleguard-hu01 cg_aws_identity
  info "rol de operación disponible durante 1 h como máximo: ${CG_AWS_ARN##*:}"
}

# do_mfa_prompt: runs INSIDE the window opened by unlock, attached to the person's keyboard.
do_mfa_prompt() {
  echo "CircleGuard HU-01 · rol de operación (sesión de 1 h como máximo)."
  echo "Escriba el código MFA del usuario circleguard-hu01-operator cuando la AWS CLI lo pida."
  if aws sts get-caller-identity --profile circleguard-hu01 --query Arn --output text >/dev/null; then
    touch "$UNLOCK_MARK"
    echo "Listo: ya puede cerrar esta ventana."
  else
    echo "No se completó: cierre la ventana y repita 'unlock'."
  fi
  read -r -p "Pulse Enter para cerrar. " _ || true
}

do_logout() {
  local kinds kind
  if [[ "$1" == all ]]; then kinds=(bootstrap operator); else kinds=("$1"); fi
  for kind in "${kinds[@]}"; do
    aws logout --profile "$(cg_login_profile "$kind")" >/dev/null 2>&1 </dev/null || true
  done
  # Role credentials derived from the sessions: the CLI cache under the protected home only
  # holds HU-01 roles. Issued credentials still expire by themselves (1 h or less).
  rm -f "$CG_AWS_HOME/.aws/cli/cache/"*.json
  for kind in "${kinds[@]}"; do show_identity "$(cg_login_profile "$kind")"; done
}

# do_cloudshell_bundle: the files teardown.sh needs, without secrets nor operator settings.
do_cloudshell_bundle() {
  local out="$CG_LOCAL_HOME/cloudshell/circleguard-teardown.tgz"
  install -d -m 700 "$(dirname "$out")"
  tar -czf "$out" -C "$REPO_DIR" infra/teardown.sh infra/teardown-cloudshell.sh infra/bootstrap/lib/common.sh \
    infra/bootstrap/lib/aws.sh infra/bootstrap/lib/session.sh infra/bootstrap/lib/budget.sh infra/config/aws.env infra/config/envs
  created "paquete para CloudShell: $(tar -tzf "$out" | grep -vc '/$') archivos, sin secretos"
  info "súbalo en CloudShell (Acciones > Cargar archivo) desde: \\\\wsl.localhost\\${WSL_DISTRO_NAME:-Ubuntu}${out//\//\\}"
}

cg_load_config
case "${1:-}" in
  init) init_home ;;
  login) do_login "${2:?indique bootstrap u operator}" ;;
  unlock) do_unlock ;;
  mfa-prompt) do_mfa_prompt ;;
  status)
    for kind in bootstrap operator; do show_identity "$(cg_login_profile "$kind")"; done
    if [[ -n "$(find "$CG_AWS_HOME/.aws/cli/cache" -name '*.json' 2>/dev/null)" ]]; then
      info "hay credenciales de rol en caché (caducan solas en 1 h como máximo)"
    fi
    ;;
  logout) do_logout "${2:?indique bootstrap, operator o all}" ;;
  cloudshell-bundle) do_cloudshell_bundle ;;
  -h | --help | "") usage ;;
  *) die "comando desconocido: $1 (ver --help)" ;;
esac
