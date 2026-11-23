#!/usr/bin/env bash
# Runs on the registry host (the nexus server, or locally with --target local) BEFORE the
# container starts, streamed by infra/bootstrap-registry.sh. Idempotent:
#   1. no other container publishes the registry port (with REGISTRY_BACKEND=distribution,
#      bootstrap-nexus.sh first moves the unused Nexus connector to a loopback standby port);
#   2. self-signed TLS certificate, created only when missing or expiring within 30 days;
#   3. htpasswd file with the "ci" user (bcrypt), rewritten only when the managed password no
#      longer verifies. The password reaches htpasswd through stdin, never as an argument.
# A running registry is restarted when 2 or 3 changed, so that it loads the new files.
#   usage: prepare.sh <stack dir> <plan|apply>
set -Eeuo pipefail

DIR=${1:?directorio del stack}
MODE=${2:-plan}
HTPASSWD_IMAGE=httpd:2.4.66-alpine
result() { echo "CG_RESULT $*"; }
fail() { echo "ERROR: $*"; exit 1; }
applying() { [[ "$MODE" == apply ]]; }

if [[ ! -f "$DIR/.env" ]]; then
  applying && fail "falta $DIR/.env"
  result PLAN "generar el certificado TLS y el usuario del registro cuando exista su .env"
  exit 0
fi
set -a
# shellcheck disable=SC1091
. "$DIR/.env"
set +a
command -v openssl >/dev/null || fail "falta openssl en el host"
USER_NAME=${REGISTRY_CI_USER:?REGISTRY_CI_USER no está definido en .env}
changed=false
# native <path>: path for native Windows programs (openssl.exe of Git Bash with --target local,
# where MSYS_NO_PATHCONV=1 disables the automatic conversion); unchanged on Linux.
if command -v cygpath >/dev/null 2>&1; then native() { cygpath -m "$1"; }; else native() { printf '%s' "$1"; }; fi

# 1. Registry port: published by this stack only.
others=$(docker ps --format '{{.Names}} {{.Ports}}' | grep -E ":$REGISTRY_HOST_PORT->" | awk '$1 != "cg-registry" { print $1 }' || true)
if [[ -n "$others" ]]; then
  applying && fail "el puerto $REGISTRY_HOST_PORT lo publica $others: ejecute antes infra/bootstrap-nexus.sh (con REGISTRY_BACKEND=distribution libera el puerto)"
  result PLAN "liberar el puerto $REGISTRY_HOST_PORT, hoy publicado por $others (infra/bootstrap-nexus.sh)"
fi

# 2. TLS: traffic inside the VPC is encrypted. Clients do not verify the server (they list the
#    tools subnet in insecure-registries); see docs/arquitectura/registro-artefactos.md.
crt="$DIR/tls/registry.crt"
key="$DIR/tls/registry.key"
if [[ -s "$crt" && -s "$key" ]] && openssl x509 -in "$(native "$crt")" -noout -checkend 2592000 >/dev/null 2>&1; then
  result UNCHANGED "certificado TLS del registro vigente hasta $(openssl x509 -in "$(native "$crt")" -noout -enddate | cut -d= -f2)"
elif applying; then
  verb=CREATED
  [[ -s "$crt" ]] && verb=UPDATED
  install -d -m 0755 "$DIR/tls"
  if ! err=$( (umask 077 && openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 \
    -subj "/CN=circleguard-registry" -addext "subjectAltName=DNS:circleguard-registry,IP:127.0.0.1" \
    -keyout "$(native "$key.tmp")" -out "$(native "$crt.tmp")") 2>&1); then
    rm -f "$key.tmp" "$crt.tmp"
    fail "openssl no pudo generar el certificado: $(tail -1 <<<"$err")"
  fi
  chmod 0644 "$crt.tmp"
  mv -f "$key.tmp" "$key"
  mv -f "$crt.tmp" "$crt"
  changed=true
  result "$verb" "certificado TLS autofirmado del registro (10 años)"
else
  result PLAN "generar el certificado TLS autofirmado del registro"
fi

# 3. htpasswd user. The helper container has no network; stdin carries the password (first line)
#    and, to verify, the current file.
file="$DIR/auth/htpasswd"
image_ready() {
  docker image inspect "$HTPASSWD_IMAGE" >/dev/null 2>&1 && return 0
  applying && docker pull -q "$HTPASSWD_IMAGE" >/dev/null
}
verify_user() {
  { printf '%s\n' "$REGISTRY_CI_PASSWORD"; cat "$file"; } |
    docker run --rm -i --network none --entrypoint sh "$HTPASSWD_IMAGE" -c \
      'IFS= read -r pw; cat >/tmp/htpasswd; printf "%s" "$pw" | htpasswd -vi /tmp/htpasswd "$1"' sh "$USER_NAME" >/dev/null 2>&1
}
if [[ -s "$file" && "$(cut -d: -f1 "$file" | sed '/^$/d')" == "$USER_NAME" ]] && image_ready && verify_user; then
  result UNCHANGED "usuario $USER_NAME del registro con la contraseña gestionada (bcrypt)"
elif applying; then
  verb=CREATED
  [[ -s "$file" ]] && verb=UPDATED
  install -d -m 0755 "$DIR/auth"
  printf '%s' "$REGISTRY_CI_PASSWORD" |
    docker run --rm -i --network none --entrypoint htpasswd "$HTPASSWD_IMAGE" -niB -C 10 "$USER_NAME" |
    sed '/^$/d' >"$file.tmp"
  [[ "$(cut -d: -f1 "$file.tmp")" == "$USER_NAME" ]] || { rm -f "$file.tmp"; fail "no se pudo generar el usuario $USER_NAME del registro"; }
  chmod 0600 "$file.tmp"
  mv -f "$file.tmp" "$file"
  changed=true
  result "$verb" "usuario $USER_NAME del registro (bcrypt, contraseña del gestor de secretos)"
else
  result PLAN "crear o verificar el usuario $USER_NAME del registro"
fi

if $changed && [[ -n "$(docker ps -q --filter name='^cg-registry$')" ]]; then
  docker restart cg-registry >/dev/null
  echo "registro reiniciado para cargar el certificado o los usuarios nuevos"
fi
