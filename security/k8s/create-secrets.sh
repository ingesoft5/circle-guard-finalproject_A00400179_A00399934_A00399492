#!/usr/bin/env bash
# HU-14 · Copies the CircleGuard secrets from AWS SSM Parameter Store (SecureString) into Kubernetes Secrets.
#
#   security/k8s/create-secrets.sh <dev|stage|prod> [--namespace circleguard] [--apply]
#
# Default is PLAN: it only prints which Secrets and keys would be created. It makes no AWS or Kubernetes call and
# reads no value. --apply needs `aws` (with access to /circleguard/<env>/*) and `kubectl` pointing at the cluster.
#
# How the values travel (they are never written to disk, to the repository or to the output):
#   aws ssm get-parameter --with-decryption  ->  shell variable  ->  printf (a builtin, not a process argument)
#   ->  pipe  ->  kubectl create secret --from-env-file=/dev/stdin --dry-run=client -o yaml  ->  pipe  ->  kubectl apply
# so `ps` never shows a value. --from-literal is deliberately NOT used: it would put the value in the process arguments.
# The catalog is security/k8s/secrets.catalog (names only). A missing parameter aborts BEFORE anything is applied.
#
# Not covered here: encryption of Secrets at rest in etcd. Kubernetes Secrets are only base64-encoded unless the cluster
# enables encryption (for EKS, envelope encryption with a KMS key). That is a cluster setting of HU-09/HU-10.

set -Eeuo pipefail
set +x

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
CATALOG="$ROOT_DIR/security/k8s/secrets.catalog"
usage() { sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }

ENV_NAME="" NAMESPACE=circleguard APPLY=0
while (($#)); do
  case "$1" in
    dev|stage|prod) ENV_NAME=$1; shift ;;
    --namespace) NAMESPACE=${2:?Falta el namespace}; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Argumento desconocido: $1" ;;
  esac
done
[[ -n "$ENV_NAME" ]] || { usage >&2; die "Indique el ambiente: dev, stage o prod."; }
[[ -f "$CATALOG" ]] || die "Falta $CATALOG"

# Catalog entries: secret | key | ssm parameter (comments and the PENDING block are lines starting with '#').
mapfile -t ENTRIES < <(grep -v -E '^[[:space:]]*(#|$)' "$CATALOG" | awk '{print $1 "|" $2 "|" $3}')
((${#ENTRIES[@]})) || die "El catálogo está vacío."
mapfile -t SECRETS < <(printf '%s\n' "${ENTRIES[@]}" | cut -d'|' -f1 | sort -u)

echo "Ambiente: $ENV_NAME · namespace: $NAMESPACE · origen: SSM /circleguard/$ENV_NAME/<PARAMETRO> · modo: $([[ $APPLY == 1 ]] && echo APPLY || echo PLAN)"
for s in "${SECRETS[@]}"; do
  keys=$(printf '%s\n' "${ENTRIES[@]}" | awk -F'|' -v s="$s" '$1 == s {printf "%s ", $2}')
  printf '  Secret %-20s claves: %s\n' "$s" "$keys"
done

if ((APPLY == 0)); then
  echo "PLAN: no se hizo ninguna llamada a AWS ni a Kubernetes. Use --apply para crear los Secrets."
  exit 0
fi

command -v aws >/dev/null 2>&1 || die "No está disponible 'aws'."
command -v kubectl >/dev/null 2>&1 || die "No está disponible 'kubectl'."

# Phase 1: read EVERY value first, keep them in memory only, and stop if one is missing or has a newline.
declare -A VALUE
for e in "${ENTRIES[@]}"; do
  IFS='|' read -r secret key param <<<"$e"
  v=$(aws ssm get-parameter --name "/circleguard/$ENV_NAME/$param" --with-decryption --query Parameter.Value --output text 2>/dev/null) ||
    die "No se pudo leer /circleguard/$ENV_NAME/$param (¿existe? ¿hay permiso?). No se aplicó nada."
  [[ -n "$v" && "$v" != "None" ]] || die "El parámetro /circleguard/$ENV_NAME/$param está vacío. No se aplicó nada."
  [[ "$v" != *$'\n'* ]] || die "El parámetro $param contiene saltos de línea y no se puede cargar con --from-env-file. No se aplicó nada."
  VALUE["$secret|$key"]=$v
done

# Phase 2: create/update each Secret from a pipe.
for s in "${SECRETS[@]}"; do
  {
    for e in "${ENTRIES[@]}"; do
      IFS='|' read -r secret key _ <<<"$e"
      # an `if`, not `[[ ]] && printf`: with pipefail a false last test would fail the whole pipeline
      if [[ "$secret" == "$s" ]]; then printf '%s=%s\n' "$key" "${VALUE[$secret|$key]}"; fi
    done
  } | kubectl create secret generic "$s" --namespace "$NAMESPACE" --from-env-file=/dev/stdin \
        --dry-run=client -o yaml |
    kubectl label --local -f - app.kubernetes.io/part-of=circleguard app.kubernetes.io/managed-by=hu-14-create-secrets \
        --dry-run=client -o yaml |
    kubectl apply --namespace "$NAMESPACE" -f - >/dev/null
  echo "Secret $s aplicado en $NAMESPACE"
done
unset VALUE
echo "APPLY: ${#SECRETS[@]} Secrets aplicados. Los valores no se escribieron en disco ni en esta salida."
