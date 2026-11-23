#!/usr/bin/env bash
# HU-14 · Fetches the kubeconfig that HU-09 publishes in AWS SSM Parameter Store (SecureString /circleguard/<env>/kubeconfig) into a
# private file, so that security/k8s/test-rbac.sh, ensure-tls-secret.sh and create-secrets.sh can reach the cluster.
#
#   KUBECONFIG=$(security/k8s/fetch-kubeconfig.sh <dev|stage|prod> [--out FILE]) security/k8s/test-rbac.sh --namespace circleguard-dev
#
# Only the PATH of the file is printed on stdout (so it can be captured); the content is never printed. The file is created with mode 600.
# Without --out a new temporary file is created and it is YOUR job to delete it when you are done (rm -f "$KUBECONFIG").
# With --out an existing file is never overwritten.
# It makes ONE read-only AWS call (ssm get-parameter --with-decryption). It changes nothing in AWS or in the cluster.
#
# Be aware: the kubeconfig that HU-09 publishes carries cluster-admin credentials. Whoever can read this parameter controls the
# cluster; limit access to it with IAM (see docs/seguridad/hu-14.md) and prefer the narrower identity of rbac/ (jenkins-deployer) for the pipeline.
# Needs the AWS CLI with permission to read the parameter. Exit code: 0 = file written; 2 = usage, tooling or AWS error.
set -Eeuo pipefail
set +x

die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
usage() { sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
need() { [[ -n "${2-}" ]] || die "$1 necesita un valor."; }

ENV_NAME="" OUT=""
while (($#)); do
  case "$1" in
    dev|stage|prod) ENV_NAME=$1; shift ;;
    --out) need "$1" "${2-}"; OUT=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Argumento desconocido: $1" ;;
  esac
done
[[ -n "$ENV_NAME" ]] || { usage >&2; die "Indique el ambiente: dev, stage o prod."; }
command -v aws >/dev/null 2>&1 || die "Falta el AWS CLI."

REGION=${AWS_REGION:-us-east-2}
PARAM=/circleguard/$ENV_NAME/kubeconfig
umask 077
if [[ -n "$OUT" ]]; then
  [[ ! -e "$OUT" ]] || die "$OUT ya existe: no se sobrescribe."
  TARGET=$OUT
else
  TARGET=$(mktemp)
fi

if ! aws ssm get-parameter --region "$REGION" --name "$PARAM" --with-decryption --query Parameter.Value --output text >"$TARGET" 2>/dev/null; then
  rm -f "$TARGET"
  die "No se pudo leer $PARAM en la región $REGION (¿existe el parámetro y tiene permiso?)."
fi
[[ -s "$TARGET" ]] || { rm -f "$TARGET"; die "El parámetro $PARAM está vacío."; }
chmod 600 "$TARGET"
printf 'kubeconfig de %s escrito en un archivo privado (modo 600).\n' "$ENV_NAME" >&2
printf '%s\n' "$TARGET"
