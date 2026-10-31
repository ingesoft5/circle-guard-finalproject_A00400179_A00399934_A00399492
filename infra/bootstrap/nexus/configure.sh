#!/usr/bin/env bash
# Runs on the Nexus host (or locally with --target local), streamed by
# infra/bootstrap-nexus.sh. Configures Nexus through its REST API, idempotently:
#   managed admin password, EULA (team decision), anonymous access off, Docker Bearer Token
#   realm and the Docker hosted repository circleguard-docker.
#   usage: configure.sh <stack dir> <plan|apply>
set -Eeuo pipefail

DIR=${1:?directorio del stack}
MODE=${2:-plan}
REPO=circleguard-docker
result() { echo "CG_RESULT $*"; }
fail() { echo "ERROR: $*"; exit 1; }
applying() { [[ "$MODE" == apply ]]; }

set -a
# shellcheck disable=SC1091
. "$DIR/.env"
set +a
URL="http://127.0.0.1:${NEXUS_HTTP_PORT}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Credentials go to curl through a config read from stdin, never as arguments.
admin_auth() { printf 'user = "admin:%s"\n' "$NEXUS_ADMIN_PASSWORD"; }
code() { curl -s -o /dev/null -w '%{http_code}' "$@" || true; }
admin_code() { admin_auth | code -K - "$@"; }
api() { # api <method> <path> [json file]: response body on stdout; fails on HTTP errors
  if (($# >= 3)); then
    admin_auth | curl -fsS -K - -X "$1" -H 'Content-Type: application/json' --data-binary "@$3" "$URL$2"
  else
    admin_auth | curl -fsS -K - -X "$1" "$URL$2"
  fi
}
py() { python3 -c "$1"; }

status=$(code "$URL/service/rest/v1/status/writable")
if [[ "$status" != 200 && "$MODE" != apply ]]; then
  result PLAN "configurar Nexus cuando el stack esté desplegado"
  exit 0
fi
for _ in $(seq 1 120); do
  [[ "$status" == 200 ]] && break
  sleep 5
  status=$(code "$URL/service/rest/v1/status/writable")
done
[[ "$status" == 200 ]] || fail "Nexus no admite escritura (HTTP $status)"
result UNCHANGED "Nexus en línea y admitiendo escritura"

# 1. Administrator: the generated initial password is replaced by the managed one.
if [[ $(admin_code "$URL/service/rest/v1/status/check") == 200 ]]; then
  result UNCHANGED "el administrador usa la contraseña gestionada"
else
  initial=$(docker exec cg-nexus cat /nexus-data/admin.password 2>/dev/null || true)
  [[ -n "$initial" ]] || fail "la contraseña gestionada no es válida y no existe admin.password: el administrador fue modificado fuera de los scripts"
  if ! applying; then
    initial=""
    result PLAN "reemplazar la contraseña inicial del administrador y aplicar la configuración por API"
    exit 0
  fi
  {
    printf 'user = "admin:%s"\n' "$initial"
    printf 'data-binary = "%s"\n' "$NEXUS_ADMIN_PASSWORD"
  } | curl -fsS -K - -X PUT -H 'Content-Type: text/plain' "$URL/service/rest/v1/security/users/admin/change-password"
  initial=""
  [[ $(admin_code "$URL/service/rest/v1/status/check") == 200 ]] || fail "la contraseña gestionada no quedó activa"
  result UPDATED "contraseña inicial del administrador reemplazada por la gestionada"
fi

# 2. EULA of the Community Edition: accepted only if the team decided so (NEXUS_ACCEPT_EULA).
eula_code=$(admin_code "$URL/service/rest/v1/system/eula")
if [[ "$eula_code" == 200 ]]; then
  api GET /service/rest/v1/system/eula >"$TMP/eula.json"
  if [[ $(py "import json; print(str(json.load(open('$TMP/eula.json')).get('accepted', False)).lower())") == true ]]; then
    result UNCHANGED "EULA de Nexus Community Edition aceptado"
  elif [[ "${NEXUS_ACCEPT_EULA:-false}" != true ]]; then
    fail "Nexus Community Edition exige aceptar su EULA. Revíselo y, si el equipo lo acepta, defina NEXUS_ACCEPT_EULA=true en infra/config/aws.env"
  elif applying; then
    py "import json; d=json.load(open('$TMP/eula.json')); d['accepted']=True; json.dump(d, open('$TMP/eula-accept.json','w'))"
    api POST /service/rest/v1/system/eula "$TMP/eula-accept.json" >/dev/null
    result UPDATED "EULA aceptado por decisión del equipo (NEXUS_ACCEPT_EULA=true)"
  else
    result PLAN "aceptar el EULA (NEXUS_ACCEPT_EULA=true)"
  fi
else
  result UNCHANGED "esta versión no requiere aceptar el EULA por API (HTTP $eula_code)"
fi

# 3. Anonymous access disabled.
api GET /service/rest/v1/security/anonymous >"$TMP/anonymous.json"
if [[ $(py "import json; print(str(json.load(open('$TMP/anonymous.json'))['enabled']).lower())") == false ]]; then
  result UNCHANGED "acceso anónimo deshabilitado"
elif applying; then
  py "import json; d=json.load(open('$TMP/anonymous.json')); d['enabled']=False; json.dump(d, open('$TMP/anonymous-off.json','w'))"
  api PUT /service/rest/v1/security/anonymous "$TMP/anonymous-off.json" >/dev/null
  result UPDATED "acceso anónimo deshabilitado"
else
  result PLAN "deshabilitar el acceso anónimo"
fi

# 4. Docker Bearer Token realm, required by Docker clients against the hosted repository.
api GET /service/rest/v1/security/realms/active >"$TMP/realms.json"
if py "import json,sys; sys.exit(0 if 'DockerToken' in json.load(open('$TMP/realms.json')) else 1)"; then
  result UNCHANGED "realm DockerToken activo"
elif applying; then
  py "import json; r=json.load(open('$TMP/realms.json')); r.append('DockerToken'); json.dump(r, open('$TMP/realms-new.json','w'))"
  api PUT /service/rest/v1/security/realms/active "$TMP/realms-new.json" >/dev/null
  result UPDATED "realm DockerToken activado"
else
  result PLAN "activar el realm DockerToken"
fi

# 5. Docker hosted repository with immutable tags (allow_once) on the connector port.
py "import json; d=json.load(open('$DIR/repositories/$REPO.json')); d['docker']['httpPort']=int('$NEXUS_DOCKER_PORT'); json.dump(d, open('$TMP/repo.json','w'))"
repo_code=$(admin_code "$URL/service/rest/v1/repositories/docker/hosted/$REPO")
if [[ "$repo_code" == 200 ]]; then
  api GET "/service/rest/v1/repositories/docker/hosted/$REPO" >"$TMP/repo-current.json"
  if py "
import json, sys
want, have = json.load(open('$TMP/repo.json')), json.load(open('$TMP/repo-current.json'))
same = (want['online'] == have['online']
        and want['storage']['writePolicy'].lower() == str(have['storage']['writePolicy']).lower()
        and want['storage']['strictContentTypeValidation'] == have['storage']['strictContentTypeValidation']
        and all(want['docker'][k] == have['docker'][k] for k in ('v1Enabled', 'forceBasicAuth', 'httpPort')))
sys.exit(0 if same else 1)"; then
    result UNCHANGED "repositorio Docker hosted $REPO (puerto ${NEXUS_DOCKER_PORT}, etiquetas inmutables)"
  elif applying; then
    api PUT "/service/rest/v1/repositories/docker/hosted/$REPO" "$TMP/repo.json" >/dev/null
    result UPDATED "repositorio Docker hosted $REPO corregido"
  else
    result PLAN "corregir el repositorio Docker hosted $REPO"
  fi
elif [[ "$repo_code" == 404 ]]; then
  if applying; then
    api POST /service/rest/v1/repositories/docker/hosted "$TMP/repo.json" >/dev/null
    result CREATED "repositorio Docker hosted $REPO (puerto ${NEXUS_DOCKER_PORT}, etiquetas inmutables)"
  else
    result PLAN "crear el repositorio Docker hosted $REPO"
  fi
else
  fail "no se pudo consultar el repositorio $REPO (HTTP $repo_code)"
fi

# 6. Final checks: anonymous REST calls are rejected and the Docker connector answers.
anonymous=$(code "$URL/service/rest/v1/repositories")
if [[ "$anonymous" == 401 || "$anonymous" == 403 ]]; then
  result UNCHANGED "API sin credenciales rechazada (HTTP $anonymous)"
else
  fail "la API respondió HTTP $anonymous sin credenciales"
fi
registry=$(code "http://127.0.0.1:${NEXUS_DOCKER_HOST_PORT}/v2/")
if [[ "$registry" == 401 ]]; then
  result UNCHANGED "registro Docker escuchando en el puerto ${NEXUS_DOCKER_HOST_PORT} y exigiendo autenticación"
elif applying; then
  fail "el conector Docker no respondió como se esperaba (HTTP $registry)"
fi
