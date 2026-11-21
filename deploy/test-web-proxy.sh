#!/usr/bin/env bash
# HU-02 · Regression test of the web client's same-origin proxy (mobile/nginx.conf): each prefix (/auth, /identity, ...) must reach its
# service WITHOUT the prefix, keeping the rest of the path and the query string.
#
# It starts the given web image next to eight tiny stub services (one per upstream name and port) that answer with the request URI
# they received, and checks the answer for every prefix. A previous version of the configuration forwarded "/" for every request
# (a variable in proxy_pass does not strip the prefix), so the web client could not call any API.
#
#   deploy/test-web-proxy.sh <web image>        e.g. localhost:5000/circleguard/circleguard-web:1.0.0
# Needs Docker. Everything it creates is removed at the end. Exit code: 0 = every prefix reaches its service as expected.
set -uo pipefail

IMAGE=${1:?Uso: deploy/test-web-proxy.sh <imagen del cliente web>}
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# The stubs use the same nginx image that the web client is built on (read from its Dockerfile, so it is always a pinned one).
STUB_IMAGE=$(sed -n 's/^ARG NGINX_IMAGE=//p' "$ROOT_DIR/mobile/Dockerfile" | head -1)
[[ -n "$STUB_IMAGE" ]] || { echo "ERROR: no se encontró NGINX_IMAGE en mobile/Dockerfile" >&2; exit 2; }
NET=cg-web-proxy-test
WORK=$(mktemp -d)
SERVICES=(auth:8180 identity:8083 dashboard:8084 file:8085 form:8086 gateway:8087 notification:8082 promotion:8088)
cleanup() {
  local names=(); for entry in "${SERVICES[@]}"; do names+=("cg-web-proxy-${entry%%:*}"); done
  docker rm -f cg-web-proxy-web "${names[@]}" >/dev/null 2>&1
  docker network rm "$NET" >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT
docker info >/dev/null 2>&1 || { echo "SKIP: Docker no está disponible"; exit 0; }
docker image inspect "$IMAGE" >/dev/null 2>&1 || { echo "ERROR: no existe la imagen $IMAGE" >&2; exit 2; }

docker network create "$NET" >/dev/null
for entry in "${SERVICES[@]}"; do
  name=${entry%%:*}; port=${entry##*:}
  printf 'server { listen %s; location / { default_type text/plain; return 200 "%s got: $request_uri"; } }\n' "$port" "$name" >"$WORK/$name.conf"
  docker run -d --name "cg-web-proxy-$name" --network "$NET" --network-alias "$name" -v "$WORK/$name.conf":/etc/nginx/conf.d/default.conf:ro "$STUB_IMAGE" >/dev/null
done
docker run -d --name cg-web-proxy-web --network "$NET" -p 127.0.0.1:18091:8080 "$IMAGE" >/dev/null
for _ in $(seq 1 40); do [[ "$(docker inspect -f '{{.State.Health.Status}}' cg-web-proxy-web 2>/dev/null)" == healthy ]] && break; sleep 2; done

PASSED=0 FAILED=0
expect() { # expect <description> <expected body> <actual body>
  if [[ "$2" == "$3" ]]; then printf 'PASS  %s -> %s\n' "$1" "$3"; PASSED=$((PASSED + 1)); else printf 'FAIL  %s: expected "%s", got "%s"\n' "$1" "$2" "$3"; FAILED=$((FAILED + 1)); fi
}
get() { curl -s -m 8 "http://127.0.0.1:18091$1"; }

for entry in "${SERVICES[@]}"; do
  name=${entry%%:*}
  expect "/$name/api/v1/ping reaches $name as /api/v1/ping" "$name got: /api/v1/ping" "$(get "/$name/api/v1/ping")"
done
expect "the query string is kept" "auth got: /api/v1/items?x=1&y=two" "$(get "/auth/api/v1/items?x=1&y=two")"
expect "the bare prefix reaches the root of the service" "identity got: /" "$(get "/identity/")"
expect "nested paths are kept" "gateway got: /api/v1/qr/validate/abc" "$(get "/gateway/api/v1/qr/validate/abc")"
expect "a POST keeps its path too" "auth got: /api/v1/auth/login" "$(curl -s -m 8 -X POST -d '{}' http://127.0.0.1:18091/auth/api/v1/auth/login)"
code=$(curl -s -o /dev/null -w '%{http_code}' -m 8 http://127.0.0.1:18091/healthz)
expect "the health endpoint of the web client still answers" "200" "$code"
code=$(curl -s -o /dev/null -w '%{http_code}' -m 8 http://127.0.0.1:18091/some/spa/route)
expect "an unknown client route still falls back to the SPA shell" "200" "$code"

printf '\n%s passed, %s failed\n' "$PASSED" "$FAILED"
((FAILED == 0))
