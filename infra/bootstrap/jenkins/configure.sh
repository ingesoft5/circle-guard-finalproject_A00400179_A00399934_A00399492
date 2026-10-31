#!/usr/bin/env bash
# Runs on the Jenkins host (or locally with --target local), streamed by
# infra/bootstrap-jenkins.sh. JCasC configures Jenkins at start-up; this script verifies the
# outcome: no setup wizard, the managed administrator logs in, anonymous users get nothing.
#   usage: configure.sh <stack dir> <plan|apply>
set -Eeuo pipefail

DIR=${1:?directorio del stack}
MODE=${2:-plan}
result() { echo "CG_RESULT $*"; }
http_code() { curl -s -o /dev/null -w '%{http_code}' "$@" || true; }
# Credentials go to curl through a config read from stdin, never as arguments.
admin_auth() { printf 'user = "%s:%s"\n' "$JENKINS_ADMIN_USER" "$JENKINS_ADMIN_PASSWORD"; }

set -a
# shellcheck disable=SC1091
. "$DIR/.env"
set +a
URL="http://127.0.0.1:${JENKINS_HTTP_PORT}"

status=$(http_code "$URL/login")
if [[ "$status" != 200 && "$MODE" != apply ]]; then
  result PLAN "verificar Jenkins cuando el stack esté desplegado"
  exit 0
fi
for _ in $(seq 1 60); do
  [[ "$status" == 200 ]] && break
  sleep 5
  status=$(http_code "$URL/login")
done
if [[ "$status" != 200 ]]; then
  echo "ERROR: Jenkins no respondió en /login (HTTP $status)"
  exit 1
fi
result UNCHANGED "Jenkins responde en /login sin asistente inicial (JCasC)"

whoami=$(admin_auth | curl -s -K - "$URL/whoAmI/api/json" || true)
if [[ "$whoami" == *'"authenticated":true'* && "$whoami" == *"\"name\":\"$JENKINS_ADMIN_USER\""* ]]; then
  result UNCHANGED "el administrador gestionado inicia sesión (contraseña del gestor de secretos)"
else
  echo "ERROR: el administrador gestionado no pudo autenticarse"
  exit 1
fi

anonymous=$(http_code "$URL/api/json")
if [[ "$anonymous" == 403 ]]; then
  result UNCHANGED "acceso anónimo denegado (HTTP 403)"
else
  echo "ERROR: el acceso anónimo devolvió HTTP $anonymous (se esperaba 403)"
  exit 1
fi

casc=$(admin_auth | http_code -K - "$URL/manage/configuration-as-code/")
if [[ "$casc" == 200 ]]; then
  result UNCHANGED "plugin Configuration as Code activo"
else
  echo "ERROR: Configuration as Code no está disponible (HTTP $casc)"
  exit 1
fi
