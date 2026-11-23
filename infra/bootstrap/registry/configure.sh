#!/usr/bin/env bash
# Runs on the registry host after `docker compose up`, streamed by infra/bootstrap-registry.sh.
# Changes nothing: checks that the registry answers over TLS, rejects anonymous requests and
# accepts the managed "ci" user. Credentials reach curl through stdin, never as arguments.
#   usage: configure.sh <stack dir> <plan|apply>
set -Eeuo pipefail

DIR=${1:?directorio del stack}
MODE=${2:-plan}
result() { echo "CG_RESULT $*"; }
fail() { echo "ERROR: $*"; exit 1; }

set -a
# shellcheck disable=SC1091
. "$DIR/.env"
set +a
URL="https://127.0.0.1:${REGISTRY_HOST_PORT}/v2/"
# -k: the certificate is self-signed (encryption without server authentication, by design).
code() { curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "$@" || true; }

anonymous=$(code "$URL")
if [[ "$anonymous" != 401 && "$MODE" != apply ]]; then
  result PLAN "comprobar el registro cuando el stack esté desplegado"
  exit 0
fi
for _ in $(seq 1 30); do
  [[ "$anonymous" == 401 ]] && break
  sleep 2
  anonymous=$(code "$URL")
done
[[ "$anonymous" == 401 ]] || fail "el registro no exige autenticación o no responde por TLS (HTTP $anonymous)"
result UNCHANGED "registro en línea por TLS y exigiendo autenticación (HTTP 401 sin credenciales)"

authenticated=$(printf 'user = "%s:%s"\n' "$REGISTRY_CI_USER" "$REGISTRY_CI_PASSWORD" | code -K - "$URL")
[[ "$authenticated" == 200 ]] || fail "el usuario $REGISTRY_CI_USER no se autentica (HTTP $authenticated)"
result UNCHANGED "el usuario $REGISTRY_CI_USER se autentica con la contraseña gestionada (HTTP 200)"
