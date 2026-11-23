#!/usr/bin/env bash
# HU-14 · Verifies the TLS of an exposed endpoint (CA10, "TLS verifiable"). It changes nothing.
#
#   security/tls/verify-tls.sh <host> <port> [--ca <ca.pem>] [--min-days <n>] [--name <expected hostname>]
#
# Checks:
#   1. the certificate chain validates against the given CA (or the system trust store when --ca is not given),
#   2. the certificate matches the expected hostname (SAN),
#   3. it does not expire within --min-days (default 14),
#   4. TLS 1.3 and TLS 1.2 are accepted,
#   5. TLS 1.1 and TLS 1.0 are rejected,
#   6. the HTTPS answer carries Strict-Transport-Security.
# Exit code: 0 = every check passed; 1 = at least one failed; 2 = usage error or the endpoint is not reachable.
set -Eeuo pipefail

HOST=${1:-}; PORT=${2:-}
[[ -n "$HOST" && -n "$PORT" ]] || { sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }
shift 2
CA="" MIN_DAYS=14 NAME=$HOST
while (($#)); do
  case "$1" in
    --ca) CA=${2:?Falta el archivo}; shift 2 ;;
    --min-days) MIN_DAYS=${2:?Falta el número}; shift 2 ;;
    --name) NAME=${2:?Falta el nombre}; shift 2 ;;
    *) echo "ERROR: argumento desconocido $1" >&2; exit 2 ;;
  esac
done
command -v openssl >/dev/null 2>&1 || { echo "ERROR: se necesita openssl" >&2; exit 2; }
[[ -z "$CA" || -f "$CA" ]] || { echo "ERROR: no existe $CA" >&2; exit 2; }

CA_ARGS=(); [[ -n "$CA" ]] && CA_ARGS=(-CAfile "$CA")
TMO=(); if command -v timeout >/dev/null 2>&1; then TMO=(timeout 15); elif command -v gtimeout >/dev/null 2>&1; then TMO=(gtimeout 15); fi
sclient() { # sclient <extra args...>; the endpoint answers or the call fails
  ${TMO[@]+"${TMO[@]}"} openssl s_client -connect "$HOST:$PORT" -servername "$NAME" "$@" </dev/null 2>&1
}

if ! sclient -brief >/dev/null 2>&1 && ! sclient >/dev/null 2>&1; then
  echo "ERROR: no se pudo conectar con $HOST:$PORT" >&2; exit 2
fi

PASSED=0 FAILED=0
result() { # result <description> <0|1>
  if [[ "$2" == 0 ]]; then printf 'PASS  %s\n' "$1"; PASSED=$((PASSED + 1)); else printf 'FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); fi
}

# The chain is valid only if the handshake succeeds WITH -verify_return_error (openssl then exits non-zero on any verification error),
# and the name is checked separately on the leaf certificate. Never infer success from text in the output.
if sclient ${CA_ARGS[@]+"${CA_ARGS[@]}"} -verify_return_error -tls1_2 >/dev/null 2>&1; then chain=0; else chain=1; fi
leaf=$(sclient -showcerts </dev/null | awk '/BEGIN CERTIFICATE/{f=1} f{print} /END CERTIFICATE/{exit}')
if [[ -n "$leaf" ]] && openssl x509 -noout -checkhost "$NAME" <<<"$leaf" 2>/dev/null | grep -q 'does match certificate'; then host=0; else host=1; fi
result "the certificate chain validates$([[ -n "$CA" ]] && echo " against $(basename "$CA")")" "$chain"
result "the certificate matches the name '$NAME'" "$host"

cert=$(sclient -showcerts </dev/null | awk '/BEGIN CERTIFICATE/{f=1} f{print} /END CERTIFICATE/{exit}')
if [[ -n "$cert" ]] && openssl x509 -noout -checkend "$((MIN_DAYS * 86400))" <<<"$cert" >/dev/null 2>&1; then left=0; else left=1; fi
end=$(openssl x509 -noout -enddate <<<"$cert" 2>/dev/null | cut -d= -f2)
result "the certificate does not expire within $MIN_DAYS days (expires: ${end:-unknown})" "$left"

sclient -tls1_3 >/dev/null 2>&1 && r=0 || r=1; result "TLS 1.3 is accepted" "$r"
sclient -tls1_2 >/dev/null 2>&1 && r=0 || r=1; result "TLS 1.2 is accepted" "$r"
# Old protocols: OpenSSL 3 refuses them at its default security level, so lower it to really try the handshake.
for proto in tls1_1 tls1; do
  if sclient "-$proto" -cipher 'DEFAULT:@SECLEVEL=0' 2>&1 | grep -q -E 'BEGIN CERTIFICATE|Cipher is [A-Za-z0-9]'; then r=1; else r=0; fi
  result "$(echo "$proto" | sed 's/tls1_1/TLS 1.1/; s/^tls1$/TLS 1.0/') is rejected" "$r"
done

if command -v curl >/dev/null 2>&1; then
  CURL_CA=(); [[ -n "$CA" ]] && CURL_CA=(--cacert "$CA")
  CT_HOST=$HOST; [[ "$HOST" == *:* ]] && CT_HOST="[$HOST]"
  headers=$(curl -s -m 15 -I ${CURL_CA[@]+"${CURL_CA[@]}"} --connect-to "$NAME:$PORT:$CT_HOST:$PORT" "https://$NAME:$PORT/" 2>/dev/null || true)
  if grep -qi '^strict-transport-security:' <<<"$headers"; then r=0; else r=1; fi
  result "the HTTPS answer carries Strict-Transport-Security" "$r"
fi

printf '\n%s passed, %s failed\n' "$PASSED" "$FAILED"
((FAILED == 0)) && echo "RESULT: PASS" || { echo "RESULT: FAIL"; exit 1; }
