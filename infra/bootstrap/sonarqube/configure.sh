#!/usr/bin/env bash
# Runs on the SonarQube host (or locally with --target local), streamed by
# infra/bootstrap-sonarqube.sh. Uses SonarQube's official Web API to replace the factory
# administrator password by the managed one and to keep anonymous access disabled.
#   usage: configure.sh <stack dir> <plan|apply>
set -Eeuo pipefail

DIR=${1:?directorio del stack}
MODE=${2:-plan}
# Documented first-start credential of SonarQube (login:password); replaced on first run.
readonly FACTORY_LOGIN="admin:admin"
result() { echo "CG_RESULT $*"; }
fail() { echo "ERROR: $*"; exit 1; }

set -a
# shellcheck disable=SC1091
. "$DIR/.env"
set +a
URL="http://127.0.0.1:${SONARQUBE_HTTP_PORT}"

system_status() {
  curl -s "$URL/api/system/status" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' 2>/dev/null || true
}
# valid <login:password>: credentials go to curl through stdin, never as arguments.
valid() { printf 'user = "%s"\n' "$1" | curl -s -K - "$URL/api/authentication/validate" | grep -q '"valid":true'; }

status=$(system_status)
if [[ "$status" != UP && "$MODE" != apply ]]; then
  result PLAN "configurar SonarQube cuando el stack esté desplegado"
  exit 0
fi
for _ in $(seq 1 120); do
  [[ "$status" == UP ]] && break
  sleep 5
  status=$(system_status)
done
[[ "$status" == UP ]] || fail "SonarQube no llegó al estado UP (estado: ${status:-sin respuesta})"
result UNCHANGED "SonarQube en estado UP con base de datos PostgreSQL persistente"

if valid "admin:$SONAR_ADMIN_PASSWORD"; then
  result UNCHANGED "el administrador usa la contraseña gestionada"
elif valid "$FACTORY_LOGIN"; then
  if [[ "$MODE" == apply ]]; then
    {
      printf 'user = "%s"\n' "$FACTORY_LOGIN"
      printf 'data-urlencode = "login=admin"\n'
      printf 'data-urlencode = "previousPassword=%s"\n' "${FACTORY_LOGIN#admin:}"
      printf 'data-urlencode = "password=%s"\n' "$SONAR_ADMIN_PASSWORD"
    } | curl -fsS -K - -o /dev/null "$URL/api/users/change_password"
    valid "admin:$SONAR_ADMIN_PASSWORD" || fail "la contraseña gestionada no quedó activa"
    result UPDATED "contraseña de fábrica del administrador reemplazada por la gestionada"
  else
    result PLAN "reemplazar la contraseña de fábrica del administrador"
  fi
else
  fail "ni la contraseña gestionada ni la de fábrica son válidas: el administrador fue modificado fuera de los scripts"
fi

anonymous=$(curl -s -o /dev/null -w '%{http_code}' "$URL/api/projects/search" || true)
if [[ "$anonymous" == 401 ]]; then
  result UNCHANGED "acceso anónimo denegado (HTTP 401, sonar.forceAuthentication)"
elif [[ "$MODE" == apply ]]; then
  {
    printf 'user = "admin:%s"\n' "$SONAR_ADMIN_PASSWORD"
    printf 'data-urlencode = "key=sonar.forceAuthentication"\n'
    printf 'data-urlencode = "value=true"\n'
  } | curl -fsS -K - -o /dev/null "$URL/api/settings/set"
  result UPDATED "sonar.forceAuthentication=true (acceso anónimo deshabilitado)"
else
  result PLAN "deshabilitar el acceso anónimo (sonar.forceAuthentication)"
fi
