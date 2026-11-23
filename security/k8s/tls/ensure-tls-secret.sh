#!/usr/bin/env bash
# HU-14 · Creates the TLS Secret "circleguard-tls" that the Ingress of HU-10 uses (deploy/k8s/components/tls).
#
#   security/k8s/tls/ensure-tls-secret.sh <dev|stage|prod> --host <dns-name or IPv4> [--days 90] [--namespace NS] [--renew] [--apply]
#
# Default is PLAN: it prints what it would do and touches nothing (no certificate is generated, no cluster call).
# --apply generates a SELF-SIGNED certificate for --host (the public IP of the node, or a name such as <ip>.sslip.io), and applies
# the Secret in the namespace circleguard-<env> (or --namespace). If the Secret already exists it is left alone unless --renew.
#
# A self-signed certificate gives an encrypted channel that is verifiable with security/tls/verify-tls.sh (using the certificate as the CA),
# but browsers will warn. For a trusted certificate use cert-manager with a real DNS name (security/k8s/tls/certificate.yaml).
#
# The private key never leaves this machine except as the Secret: it is created in a private temporary directory (mode 700) that is
# removed on exit, it is not printed, and it is not a process argument. Nothing is written to the repository.
# Needs: openssl (1.1.1 or newer) and, with --apply, kubectl pointing at the cluster (KUBECONFIG, or security/k8s/fetch-kubeconfig.sh).
# Exit code: 0 = done (or planned); 2 = usage, tooling or cluster error.
set -Eeuo pipefail
set +x

usage() { sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
need() { [[ -n "${2-}" ]] || die "$1 necesita un valor."; }   # a missing or empty option value is a usage error (exit 2)

ENV_NAME="" HOST="" DAYS=90 NAMESPACE="" RENEW=0 APPLY=0
while (($#)); do
  case "$1" in
    dev|stage|prod) ENV_NAME=$1; shift ;;
    --host) need "$1" "${2-}"; HOST=$2; shift 2 ;;
    --days) need "$1" "${2-}"; DAYS=$2; shift 2 ;;
    --namespace) need "$1" "${2-}"; NAMESPACE=$2; shift 2 ;;
    --renew) RENEW=1; shift ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Argumento desconocido: $1" ;;
  esac
done
[[ -n "$ENV_NAME" ]] || { usage >&2; die "Indique el ambiente: dev, stage o prod."; }
[[ -n "$HOST" ]] || die "--host es obligatorio (la IP pública del nodo o un nombre DNS)."
[[ "$DAYS" =~ ^[0-9]+$ && "$DAYS" -ge 1 && "$DAYS" -le 398 ]] || die "--days debe estar entre 1 y 398."
NAMESPACE=${NAMESPACE:-circleguard-$ENV_NAME}
[[ "$NAMESPACE" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || die "Namespace inválido: $NAMESPACE"

if [[ "$HOST" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
  for octet in "${BASH_REMATCH[@]:1}"; do ((10#$octet <= 255)) || die "--host no es una IPv4 válida: '$HOST'"; done
  SAN="IP:$HOST"
elif [[ "$HOST" =~ ^[A-Za-z0-9]([-A-Za-z0-9.]*[A-Za-z0-9])?$ && ${#HOST} -le 253 && "${HOST##*.}" =~ [A-Za-z] ]]; then
  SAN="DNS:$HOST"        # the last label must contain a letter: a name made only of digits and dots is a malformed IP, not a host name
else
  die "--host no es una IP ni un nombre DNS válido: '$HOST'"
fi

printf 'Secret circleguard-tls en el namespace %s · certificado autofirmado para %s · %s días\n' "$NAMESPACE" "$SAN" "$DAYS"
if ((APPLY == 0)); then
  echo "PLAN: no se genera ningún certificado ni se llama al clúster. Use --apply para ejecutarlo."
  exit 0
fi

command -v openssl >/dev/null 2>&1 || die "Falta openssl."
command -v kubectl >/dev/null 2>&1 || die "Falta kubectl."
if kubectl -n "$NAMESPACE" get secret circleguard-tls >/dev/null 2>&1 && ((RENEW == 0)); then
  echo "El Secret circleguard-tls ya existe en $NAMESPACE: no se cambia (use --renew para reemplazarlo)."
  exit 0
fi

umask 077
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -days "$DAYS" -subj "/CN=$HOST" -addext "subjectAltName=$SAN" \
  -keyout "$WORK/tls.key" -out "$WORK/tls.crt" >/dev/null 2>&1 || die "openssl no pudo generar el certificado."
kubectl -n "$NAMESPACE" create secret tls circleguard-tls --cert="$WORK/tls.crt" --key="$WORK/tls.key" --dry-run=client -o yaml \
  | kubectl -n "$NAMESPACE" apply -f - >/dev/null || die "kubectl no pudo aplicar el Secret."
echo "Secret circleguard-tls aplicado en $NAMESPACE. Verifíquelo con security/tls/verify-tls.sh."
