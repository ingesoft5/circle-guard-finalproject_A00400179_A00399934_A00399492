#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$ROOT_DIR/deploy/lib.sh"

ENV_NAME=${1:?uso: smoke-k8s.sh <dev|stage|prod>}
cg_validate_env "$ENV_NAME"
AWS_REGION=${AWS_REGION:-us-east-2}
NAMESPACE=circleguard-$ENV_NAME

if [[ -z "${KUBECONFIG:-}" ]]; then
  KUBECONFIG=$(mktemp)
  chmod 600 "$KUBECONFIG"
  trap 'rm -f "$KUBECONFIG"' EXIT
  aws ssm get-parameter --region "$AWS_REGION" --name "/circleguard/$ENV_NAME/kubeconfig" --with-decryption --query Parameter.Value --output text > "$KUBECONFIG"
  export KUBECONFIG
fi

failed=0
for item in auth:8180 identity:8083 dashboard:8084 file:8085 form:8086 gateway:8087 notification:8082 promotion:8088; do
  svc=${item%%:*}
  port=${item##*:}
  body=$(kubectl get --raw "/api/v1/namespaces/$NAMESPACE/services/$svc:$port/proxy/actuator/health/readiness" 2>&1) || body="sin respuesta: $body"
  if grep -q '"status":"UP"' <<<"$body"; then
    cg_info "OK   $svc readiness UP"
  else
    cg_info "FALLA $svc: $body"
    failed=1
  fi
done

body=$(kubectl get --raw "/api/v1/namespaces/$NAMESPACE/services/web:8080/proxy/healthz" 2>&1) || body="sin respuesta: $body"
if grep -q '^ok' <<<"$body"; then
  cg_info "OK   web healthz"
else
  cg_info "FALLA web: $body"
  failed=1
fi

[[ "$failed" == 0 ]] || cg_die "Smoke test de $ENV_NAME falló."
cg_info "Smoke test de $ENV_NAME correcto"
