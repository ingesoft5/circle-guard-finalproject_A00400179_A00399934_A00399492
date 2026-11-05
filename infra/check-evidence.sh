#!/usr/bin/env bash
# HU-01 · Read-only check of an evidence folder before versioning it (for example the masked/
# output of test-idempotency.sh or test-isolation.sh). No AWS call; it never prints the account id
# nor any secret, only counts. Exit code 1 when anything that must not be versioned is found.
#   usage: infra/check-evidence.sh <folder>

# shellcheck source=bootstrap/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/aws.sh
source "$INFRA_DIR/bootstrap/lib/aws.sh"

usage() {
  cat <<'EOF'
Uso: infra/check-evidence.sh <carpeta>
  Cuenta, sin mostrarlos, el número de cuenta, IP públicas completas, claves o identificadores de AWS,
  llaves privadas, asignaciones de secretos, hashes de archivos secretos, rutas personales y valores
  de los secretos locales en los archivos de la carpeta. Termina con código 1 si encuentra alguno.
EOF
}

cg_parse_flags "$@"
dir=${CG_ARGS[0]:-}
[[ -d "$dir" ]] || die "indique una carpeta existente (infra/check-evidence.sh <carpeta>)"
cg_load_config
export LC_ALL=C.UTF-8
FOUND=0
count() { # count <description> <n>
  if (($2 == 0)); then log PASS "$1: 0"; else log FAIL "$1: $2"; FOUND=$((FOUND + 1)); fi
}
matches() { grep "$@" || true; } # no match is not an error here (nor a trip of the ERR trap)

log INFO "carpeta: $dir · $(find "$dir" -type f | wc -l) archivos"
account=$(matches -m1 -ohE 'arn:aws:iam::[0-9]{12}:' "$CG_AWS_CONFIG" 2>/dev/null | cut -d: -f5)
if [[ "$account" =~ ^[0-9]{12}$ ]]; then
  count "archivos con el número de cuenta (****${account: -4})" "$(matches -rlF -- "$account" "$dir" | wc -l)"
else
  log WARN "sin la configuración de AWS local no se puede buscar el número de cuenta propio"
fi
count "números sueltos de 12 dígitos (salvo Canonical)" "$(matches -rhoP '(?<![0-9A-Fa-f])\d{12}(?![0-9A-Fa-f])' "$dir" | matches -vc '^099720109477$')"
count "IPv4 públicas completas" "$(matches -rhoP '(?<![\d.])\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(?![\d.])' "$dir" | matches -vE '^(10\.|127\.|0\.0\.0\.0|169\.254\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)' | sort -u | wc -l)"
count "archivos con claves o identificadores únicos de AWS, o llaves privadas" "$(matches -rlE '(AKIA|ASIA|AROA|AIDA)[A-Z0-9]{12,}|BEGIN [A-Z ]*PRIVATE KEY' "$dir" | wc -l)"
count "asignaciones de secretos (NOMBRE=valor)" "$(matches -rhoE '\b[A-Z_]*(PASSWORD|SECRET|TOKEN|SALT)[A-Z_]*=[^[:space:]]+' "$dir" | wc -l)"
count "hashes de .env, htpasswd o llaves sin omitir" "$(matches -rhE '[0-9a-f]{64} +/opt/circleguard/[^ ]*(\.env|htpasswd|\.key)$' "$dir" | wc -l)"
count "archivos con rutas personales (/home/<usuario>)" "$(matches -rlE '/home/[a-z_][a-z0-9_-]*' "$dir" | wc -l)"
if [[ -d "$CG_LOCAL_HOME/secrets" ]]; then
  hits=0
  while IFS= read -r -d '' f; do
    value=$(cat "$f")
    ((${#value} >= 8)) && grep -rqF -- "$value" "$dir" && hits=$((hits + 1))
  done < <(find "$CG_LOCAL_HOME/secrets" -type f -print0)
  value=""
  count "valores de secretos locales presentes" "$hits"
fi
log SUMMARY "check-evidence hallazgos=$FOUND"
[[ "$FOUND" -eq 0 ]] || exit 1
