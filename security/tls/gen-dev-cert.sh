#!/usr/bin/env bash
# HU-14 · Generates a DEVELOPMENT certificate chain (a private CA and a server certificate signed by it) for local TLS tests.
#
#   security/tls/gen-dev-cert.sh [--out <dir>] [--days <n>] [--host <name>]...
#
# THIS IS FOR DEVELOPMENT ONLY. The CA is created on the spot and trusted by nobody; the certificate says so in its subject.
# Do not use it for a real environment: production certificates come from a real CA (cert-manager with Let's Encrypt, or ACM),
# see docs/seguridad/hu-14.md. The private keys stay in the output directory (default security/tls/dev/, which is git-ignored:
# *.pem and *.key are in .gitignore) with mode 600. Nothing is printed except file names and the fingerprint.
#
# Output: ca.pem (trust this on the client), server.pem (certificate), server.key (private key), fullchain.pem (server + CA).
# Key type: ECDSA P-256. Default validity: 30 days. Default names: localhost, 127.0.0.1.
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
OUT="$ROOT_DIR/security/tls/dev"
DAYS=30
HOSTS=()
while (($#)); do
  case "$1" in
    --out) OUT=${2:?Falta el directorio}; shift 2 ;;
    --days) DAYS=${2:?Falta el número de días}; shift 2 ;;
    --host) HOSTS+=("${2:?Falta el nombre}"); shift 2 ;;
    -h|--help) sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "ERROR: argumento desconocido $1" >&2; exit 2 ;;
  esac
done
((${#HOSTS[@]})) || HOSTS=(localhost 127.0.0.1)
command -v openssl >/dev/null 2>&1 || { echo "ERROR: se necesita openssl" >&2; exit 2; }
[[ "$DAYS" =~ ^[0-9]+$ && "$DAYS" -ge 1 ]] || { echo "ERROR: --days debe ser un entero positivo" >&2; exit 2; }

umask 077
mkdir -p "$OUT"

# subjectAltName: IPs and DNS names are different entries
san=""
for h in "${HOSTS[@]}"; do
  if [[ "$h" =~ ^[0-9.]+$ || "$h" == *:* ]]; then san+="IP:$h,"; else san+="DNS:$h,"; fi
done
san=${san%,}

openssl ecparam -name prime256v1 -genkey -noout -out "$OUT/ca.key" 2>/dev/null
openssl req -x509 -new -key "$OUT/ca.key" -sha256 -days "$((DAYS + 30))" -out "$OUT/ca.pem" \
  -subj "/O=CircleGuard DEV ONLY/CN=CircleGuard development CA (do not trust)" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:0" -addext "keyUsage=critical,keyCertSign,cRLSign"

openssl ecparam -name prime256v1 -genkey -noout -out "$OUT/server.key" 2>/dev/null
openssl req -new -key "$OUT/server.key" -out "$OUT/server.csr" -subj "/O=CircleGuard DEV ONLY/CN=${HOSTS[0]}"
printf 'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=serverAuth\nsubjectAltName=%s\n' "$san" >"$OUT/server.ext"
openssl x509 -req -in "$OUT/server.csr" -CA "$OUT/ca.pem" -CAkey "$OUT/ca.key" -CAcreateserial -out "$OUT/server.pem" \
  -days "$DAYS" -sha256 -extfile "$OUT/server.ext" 2>/dev/null
cat "$OUT/server.pem" "$OUT/ca.pem" >"$OUT/fullchain.pem"
rm -f "$OUT/server.csr" "$OUT/server.ext" "$OUT/ca.srl"
chmod 600 "$OUT"/*.key; chmod 644 "$OUT"/*.pem

echo "Certificado de DESARROLLO generado en $OUT"
echo "  nombres:  ${HOSTS[*]}"
echo "  vigencia: $DAYS días (hasta $(openssl x509 -in "$OUT/server.pem" -noout -enddate | cut -d= -f2))"
echo "  huella:   $(openssl x509 -in "$OUT/server.pem" -noout -fingerprint -sha256 | cut -d= -f2)"
