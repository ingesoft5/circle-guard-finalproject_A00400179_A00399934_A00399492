#!/usr/bin/env bash
# HU-14 · Real TLS test: starts the TLS terminator (security/tls/nginx-tls.conf) in a throwaway container in front of a plain backend, with a
# DEVELOPMENT certificate generated on the spot, and runs security/tls/verify-tls.sh against it, including cases that must FAIL.
# Needs Docker, openssl and curl. Everything is removed at the end. Usage: security/tests/test-tls.sh    Exit code: 0 = as expected.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
IMAGE=nginxinc/nginx-unprivileged:1.27-alpine@sha256:65e3e85dbaed8ba248841d9d58a899b6197106c23cb0ff1a132b7bfe0547e4c0   # the one HU-02 pins
NET=hu14-tls-test; BACKEND=hu14-tls-backend; PROXY=hu14-tls-proxy
HTTPS_PORT=${HU14_TLS_PORT:-18443}; HTTP_PORT=${HU14_TLS_HTTP_PORT:-18080}
WORK=$(mktemp -d)
cleanup() { docker rm -f "$PROXY" "$BACKEND" >/dev/null 2>&1; docker network rm "$NET" >/dev/null 2>&1; rm -rf "$WORK"; }
trap cleanup EXIT
PASSED=0 FAILED=0
ok() { printf 'PASS  %s\n' "$1"; PASSED=$((PASSED + 1)); }
bad() { printf 'FAIL  %s\n----\n%s\n----\n' "$1" "${2:-}"; FAILED=$((FAILED + 1)); }
docker info >/dev/null 2>&1 || { echo "SKIP: Docker no está disponible"; exit 0; }

bash "$ROOT/security/tls/gen-dev-cert.sh" --out "$WORK/good" --days 30 >/dev/null || { echo "ERROR: no se pudo generar el certificado"; exit 2; }
bash "$ROOT/security/tls/gen-dev-cert.sh" --out "$WORK/other" --days 30 >/dev/null
# The unprivileged nginx runs as uid 101: in this test the DEV key has to be readable by it.
chmod 644 "$WORK/good/server.key"

docker network create "$NET" >/dev/null
docker run -d --name "$BACKEND" --network "$NET" --network-alias web "$IMAGE" >/dev/null
docker run -d --name "$PROXY" --network "$NET" -p "127.0.0.1:$HTTPS_PORT:8443" -p "127.0.0.1:$HTTP_PORT:8080" \
  -v "$WORK/good/fullchain.pem:/etc/nginx/tls/fullchain.pem:ro" -v "$WORK/good/server.key:/etc/nginx/tls/server.key:ro" \
  -v "$ROOT/security/tls/nginx-tls.conf:/etc/nginx/conf.d/default.conf:ro" "$IMAGE" >/dev/null
for _ in $(seq 1 30); do curl -s -o /dev/null -m 2 "http://127.0.0.1:$HTTP_PORT/healthz" && break; sleep 1; done

VERIFY="$ROOT/security/tls/verify-tls.sh"
out=$(bash "$VERIFY" 127.0.0.1 "$HTTPS_PORT" --ca "$WORK/good/ca.pem" --name localhost 2>&1); rc=$?
if [[ $rc == 0 && "$out" == *"RESULT: PASS"* ]]; then ok "the terminator passes every TLS check with the right CA"; else bad "verify with the right CA" "$out"; fi
printf '%s\n' "$out" | sed 's/^/      /'

out=$(bash "$VERIFY" 127.0.0.1 "$HTTPS_PORT" --ca "$WORK/other/ca.pem" --name localhost 2>&1); rc=$?
[[ $rc == 1 && "$out" == *"FAIL  the certificate chain validates"* ]] && ok "a different CA does not validate the chain" || bad "wrong CA" "$out"

out=$(bash "$VERIFY" 127.0.0.1 "$HTTPS_PORT" --ca "$WORK/good/ca.pem" --name wrong.example.invalid 2>&1); rc=$?
[[ $rc == 1 && "$out" == *"FAIL  the certificate matches the name"* && "$out" == *"PASS  the certificate chain validates"* ]] && ok "a hostname that is not in the certificate is rejected (the chain itself is fine)" || bad "wrong hostname" "$out"

out=$(bash "$VERIFY" 127.0.0.1 "$HTTPS_PORT" --ca "$WORK/good/ca.pem" --name localhost --min-days 365 2>&1); rc=$?
[[ $rc == 1 && "$out" == *"FAIL  the certificate does not expire within 365 days"* ]] && ok "a certificate that expires too soon is reported" || bad "expiry" "$out"

out=$(bash "$VERIFY" 127.0.0.1 "$HTTPS_PORT" --name localhost 2>&1); rc=$?
[[ $rc == 1 && "$out" == *"FAIL  the certificate chain validates"* ]] && ok "the system trust store does not trust the development CA" || bad "system trust store" "$out"

out=$(bash "$VERIFY" 127.0.0.1 1 2>&1); rc=$?
[[ $rc == 2 ]] && ok "an unreachable endpoint is an error (exit 2), never a pass" || bad "unreachable" "$out"

code=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "http://127.0.0.1:$HTTP_PORT/")
[[ "$code" == 301* && "$code" == *https://* ]] && ok "plain HTTP only redirects to HTTPS ($code)" || bad "http redirect" "$code"
code=$(curl -s -o /dev/null -w '%{http_code}' --cacert "$WORK/good/ca.pem" --resolve localhost:$HTTPS_PORT:127.0.0.1 "https://localhost:$HTTPS_PORT/")
[[ "$code" == 200 ]] && ok "the application answers through TLS (200 from the backend)" || bad "proxy through TLS" "$code"

printf '\n%s passed, %s failed\n' "$PASSED" "$FAILED"
((FAILED == 0))
