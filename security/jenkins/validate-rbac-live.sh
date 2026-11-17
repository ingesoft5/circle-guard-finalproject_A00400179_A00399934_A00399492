#!/usr/bin/env bash
# HU-14 · Validates the role-based access of the Jenkins of HU-01 against a REAL controller built from the project's OWN files
# (infra/bootstrap/jenkins/plugins.txt and casc/jenkins.yaml), started for the test and destroyed afterwards (a container on
# 127.0.0.1 with random passwords that are never printed). It does not touch the Jenkins that bootstrap-jenkins.sh deploys.
#
#   security/jenkins/validate-rbac-live.sh [--keep]     (--keep leaves the container and image for inspection)
#
# It builds a throwaway image (base: the Jenkins LTS used by HU-01, plus ALL the plugins of plugins.txt), starts it with the real
# casc/jenkins.yaml, and checks with HTTP requests what each user (anonymous, viewer, developer, admin) can and cannot do.
# Requires Docker and network access to download the plugins. Exit code: 0 = every check as expected; 1 = a mismatch; 2 = could not run.
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
BASE_IMAGE=${JENKINS_BASE_IMAGE:-jenkins/jenkins:2.580.2-lts-jdk21}   # same LTS line as infra/bootstrap/jenkins/Dockerfile
IMAGE=hu14-jenkins-rbac:test
NAME=hu14-jenkins-rbac
PORT=${HU14_JENKINS_PORT:-18080}
KEEP=0; [[ "${1:-}" == --keep ]] && KEEP=1
WORK=$(mktemp -d)
cleanup() {
  rm -rf "$WORK"
  if ((KEEP == 0)); then docker rm -f "$NAME" >/dev/null 2>&1 || true; docker rmi -f "$IMAGE" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT
die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 || die "Docker no está disponible."

# Random credentials, kept in files with mode 600 inside a temporary directory (curl reads them with -K; never on a command line).
umask 077
rand() { head -c 18 /dev/urandom | base64 | tr -d '=+/' | cut -c1-20; }
ADMIN_USER=hu14-admin; DEV_USER=hu14-dev; VIEWER_USER=hu14-viewer
ADMIN_PW=$(rand); DEV_PW=$(rand); VIEWER_PW=$(rand)
for u in ADMIN DEV VIEWER; do
  user_var="${u}_USER"; pw_var="${u}_PW"
  printf 'user = "%s:%s"\n' "${!user_var}" "${!pw_var}" >"$WORK/auth-$u.cfg"
done

cp "$ROOT_DIR/infra/bootstrap/jenkins/casc/jenkins.yaml" "$WORK/jenkins.yaml"
cp "$ROOT_DIR/infra/bootstrap/jenkins/plugins.txt" "$WORK/plugins.txt"
cat >"$WORK/Dockerfile" <<EOF
FROM $BASE_IMAGE
COPY --chmod=644 plugins.txt /tmp/plugins.txt
RUN jenkins-plugin-cli --plugin-file /tmp/plugins.txt
USER root
RUN mkdir -p /casc && chmod 755 /casc
COPY --chown=jenkins:jenkins --chmod=644 jenkins.yaml /casc/jenkins.yaml
USER jenkins
EOF
echo "==> building the throwaway Jenkins image (downloads the plugins)"
docker build -q -t "$IMAGE" "$WORK" >/dev/null || die "No se pudo construir la imagen (¿hay red para descargar los plugins?)."

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -p "127.0.0.1:$PORT:8080" \
  -e CASC_JENKINS_CONFIG=/casc/jenkins.yaml -e JAVA_OPTS="-Djenkins.install.runSetupWizard=false" -e CG_JENKINS_URL="http://localhost:$PORT/" \
  -e JENKINS_ADMIN_USER="$ADMIN_USER" -e JENKINS_ADMIN_PASSWORD="$ADMIN_PW" \
  -e JENKINS_DEV_USER="$DEV_USER" -e JENKINS_DEV_PASSWORD="$DEV_PW" \
  -e JENKINS_VIEWER_USER="$VIEWER_USER" -e JENKINS_VIEWER_PASSWORD="$VIEWER_PW" \
  "$IMAGE" >/dev/null || die "No se pudo iniciar el contenedor."

URL="http://127.0.0.1:$PORT"
code() { curl -s -o /dev/null -w '%{http_code}' "$@" || true; }
echo "==> waiting for Jenkins to start"
for _ in $(seq 1 90); do
  [[ "$(code "$URL/login")" == 200 ]] && break
  # fail fast if the controller died (for example a configuration error) instead of waiting the full time
  [[ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" == true ]] || break
  sleep 3
done
[[ "$(code "$URL/login")" == 200 ]] || { docker logs "$NAME" 2>&1 | tail -15 >&2; die "Jenkins no arrancó."; }

PASSED=0 FAILED=0
expect() { # expect <description> <expected code> <actual code>
  if [[ "$2" == "$3" ]]; then printf 'PASS  %s -> %s\n' "$1" "$3"; PASSED=$((PASSED + 1)); else printf 'FAIL  %s: expected %s, got %s\n' "$1" "$2" "$3"; FAILED=$((FAILED + 1)); fi
}
as() { local who=$1; shift; curl -s -K "$WORK/auth-$who.cfg" "$@"; }
status_as() { local who=$1; shift; as "$who" -o /dev/null -w '%{http_code}' "$@" || true; }
# POST with CSRF crumb: the crumb is tied to the session, so keep a cookie jar per user.
post_as() { # post_as <who> <path> [curl args...]
  local who=$1 path=$2; shift 2; local jar="$WORK/jar-$who"
  local crumb; crumb=$(as "$who" -c "$jar" -b "$jar" "$URL/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,%22:%22,//crumb)" || true)
  curl -s -K "$WORK/auth-$who.cfg" -c "$jar" -b "$jar" -H "$crumb" -o /dev/null -w '%{http_code}' -X POST "$@" "$URL$path" || true
}

echo "==> checks"
expect "anonymous cannot read the API"                          403 "$(code "$URL/api/json")"
expect "viewer can read the API"                                200 "$(status_as VIEWER "$URL/api/json")"
expect "developer can read the API"                             200 "$(status_as DEV "$URL/api/json")"
expect "admin can read the API"                                 200 "$(status_as ADMIN "$URL/api/json")"
expect "admin can open the management page"                     200 "$(status_as ADMIN "$URL/manage/")"
expect "developer cannot open the management page"              403 "$(status_as DEV "$URL/manage/")"
expect "viewer cannot open the management page"                 403 "$(status_as VIEWER "$URL/manage/")"
expect "developer cannot open the plugin manager"               403 "$(status_as DEV "$URL/manage/pluginManager/")"
expect "developer cannot open the script console"               403 "$(status_as DEV "$URL/manage/script")"

JOB='<?xml version="1.1" encoding="UTF-8"?><project><description>HU-14 RBAC test job</description><builders/></project>'
expect "developer cannot create jobs"                           403 "$(post_as DEV "/createItem?name=forbidden" -H 'Content-Type: application/xml' --data "$JOB")"
expect "admin can create a job"                                 200 "$(post_as ADMIN "/createItem?name=demo" -H 'Content-Type: application/xml' --data "$JOB")"
expect "viewer cannot build the job"                            403 "$(post_as VIEWER "/job/demo/build")"
expect "anonymous cannot build the job"                         403 "$(code -X POST "$URL/job/demo/build")"
expect "developer can build the job"                            201 "$(post_as DEV "/job/demo/build")"
expect "developer cannot delete the job"                        403 "$(post_as DEV "/job/demo/doDelete")"
expect "viewer cannot delete the job"                           403 "$(post_as VIEWER "/job/demo/doDelete")"
expect "admin can delete the job"                               302 "$(post_as ADMIN "/job/demo/doDelete")"

printf '\n%s passed, %s failed\n' "$PASSED" "$FAILED"
((FAILED == 0))
