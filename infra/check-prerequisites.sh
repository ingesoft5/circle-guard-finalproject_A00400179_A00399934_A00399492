#!/usr/bin/env bash
# HU-01 · Read-only check of the workstation before operating or rebuilding the platform (first
# step of the reconstruction rehearsal, infra/README.md). No AWS call; changes nothing.
#   PASS ready · WARN works with a caveat · INFO context · FAIL fix it before continuing
# Exit code 1 when any check fails.

# shellcheck source=bootstrap/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/aws.sh
source "$INFRA_DIR/bootstrap/lib/aws.sh"

usage() {
  cat <<'EOF'
Uso: infra/check-prerequisites.sh
  Comprueba, sin llamar a AWS ni cambiar nada, que esta estación de trabajo puede ejecutar los
  scripts de HU-01 (herramientas, plataforma, repositorio, finales de línea y configuración).
EOF
}

PASSES=0 WARNS=0 FAILS=0
pass() { PASSES=$((PASSES + 1)); log PASS "$@"; }
warning() { WARNS=$((WARNS + 1)); log WARN "$@"; }
failure() { FAILS=$((FAILS + 1)); log FAIL "$@"; }

cg_parse_flags "$@"
((${#CG_ARGS[@]} == 0)) || die "opción desconocida: ${CG_ARGS[0]}"

# 1. Platform: the AWS CLI, SSH keys and --target local are documented for WSL Ubuntu.
pass "Bash ${BASH_VERSION%%(*} (se requiere 4 o superior)"
case "$(uname -s)" in
  Linux)
    distro=$(sed -n 's/^PRETTY_NAME="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' /etc/os-release 2>/dev/null || true)
    if grep -qi microsoft /proc/version 2>/dev/null; then pass "plataforma: WSL (${distro:-Linux})"; else pass "plataforma: Linux (${distro:-$(uname -r)})"; fi
    ;;
  MINGW* | MSYS* | CYGWIN*) warning "plataforma: Git Bash. Use WSL Ubuntu para AWS y --target local (NTFS no aplica permisos POSIX)" ;;
  *) warning "plataforma no probada: $(uname -s)" ;;
esac

# 2. Tools.
for c in ssh ssh-keygen curl python3 tar git sha256sum openssl; do
  if command -v "$c" >/dev/null 2>&1; then pass "herramienta: $c"; else failure "falta la herramienta $c"; fi
done
aws_version=$(env "${CG_AWS_ENV[@]}" aws --version 2>&1 || true)
case "$aws_version" in
  aws-cli/2.*) pass "AWS CLI ${aws_version%% *}" ;;
  aws-cli/*) failure "AWS CLI ${aws_version%% *}: se requiere la versión 2 (infra/README.md, Prerrequisitos)" ;;
  *) failure "falta AWS CLI v2 (se espera en ~/.local/bin/aws; infra/README.md, Prerrequisitos)" ;;
esac
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  pass "Docker $(docker version --format '{{.Server.Version}}' 2>/dev/null) (Gitleaks y --target local)"
else
  warning "Docker no disponible: solo hace falta para scan-secrets.sh y --target local"
fi

# 3. Repository: clean tree, LF line endings in the scripts, ignored local settings.
cd "$REPO_DIR" || die "no se puede entrar en $REPO_DIR"
if git rev-parse --git-dir >/dev/null 2>&1; then
  pass "repositorio: rama $(git rev-parse --abbrev-ref HEAD), commit $(git rev-parse --short HEAD)"
  # Tracked files only and bounded: from WSL on a Windows (or OneDrive) folder, git status may take
  # many minutes; the rehearsal clones into the WSL file system, where it is immediate.
  if ! changes=$(timeout 90 git status --porcelain --untracked-files=no 2>/dev/null); then
    warning "git status no respondió en 90 s (repositorio en una carpeta de Windows): clone en el sistema de archivos de WSL"
  elif [[ -z "$changes" ]]; then
    pass "árbol de trabajo limpio (archivos versionados)"
  else
    warning "árbol de trabajo con cambios sin confirmar: el ensayo debe hacerse sobre un commit"
  fi
else
  failure "no es un repositorio Git"
fi
crlf=$(git ls-files 'infra/*.sh' 'infra/**/*.sh' | xargs grep -lU $'\r' 2>/dev/null || true)
if [[ -z "$crlf" ]]; then pass "scripts con finales de línea LF"; else failure "scripts con CRLF (vuelva a obtenerlos: git checkout -- infra): $(tr '\n' ' ' <<<"$crlf")"; fi
if [[ -f infra/config/operator.local.env ]]; then
  if git check-ignore -q infra/config/operator.local.env; then pass "infra/config/operator.local.env presente e ignorado por Git"; else failure "infra/config/operator.local.env NO está ignorado por Git"; fi
else
  pass "sin infra/config/operator.local.env: ADMIN_CIDRS será la IP pública actual (/32)"
fi

# 4. Configuration and local state (where secrets and sessions live).
cg_load_config
pass "configuración: región $AWS_REGION/$AWS_AZ, REGISTRY_BACKEND=$REGISTRY_BACKEND, ENV_SERVERS=${ENV_SERVERS:-ninguno}, QUOTA_VCPU_LIMIT=$QUOTA_VCPU_LIMIT"
case "$CG_LOCAL_HOME" in
  *OneDrive*) failure "CG_LOCAL_HOME ($CG_LOCAL_HOME) está en OneDrive: los secretos locales no deben sincronizarse" ;;
  *) pass "secretos y sesiones locales fuera de OneDrive ($CG_LOCAL_HOME)" ;;
esac
if [[ -d "$CG_AWS_HOME" ]]; then info "sesiones AWS: $CG_AWS_HOME existe (ejecute infra/aws-session.sh status)"; else info "sesiones AWS: $CG_AWS_HOME no existe todavía (infra/aws-session.sh init lo crea)"; fi
keys=$(find "$SSH_KEY_DIR" -maxdepth 1 -name "$PROJECT-*" ! -name '*.pub' 2>/dev/null | wc -l)
info "llaves SSH locales: $keys de 4 en $SSH_KEY_DIR (bootstrap-secrets.sh --apply restaura las que falten desde SSM)"

log SUMMARY "check-prerequisites pass=$PASSES warn=$WARNS fail=$FAILS"
((FAILS == 0))
