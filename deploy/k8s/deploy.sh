#!/usr/bin/env bash
set -Eeuo pipefail

K8S_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$K8S_DIR/../.." && pwd)
source "$ROOT_DIR/deploy/lib.sh"

ENV_NAME=${1:?uso: deploy.sh <dev|stage|prod> <version>}
VERSION=${2:?uso: deploy.sh <dev|stage|prod> <version>}
case "$ENV_NAME" in dev|stage|prod) ;; *) cg_die "Ambiente inválido: $ENV_NAME" ;; esac
cg_validate_semver "$VERSION"

AWS_REGION=${AWS_REGION:-us-east-2}
NAMESPACE=circleguard-$ENV_NAME
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY=${ECR_REGISTRY:-$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com}

if [[ -z "${KUBECONFIG:-}" ]]; then
  KUBECONFIG=$(mktemp)
  chmod 600 "$KUBECONFIG"
  trap 'rm -f "$KUBECONFIG"' EXIT
  aws ssm get-parameter --region "$AWS_REGION" --name "/circleguard/$ENV_NAME/kubeconfig" --with-decryption --query Parameter.Value --output text > "$KUBECONFIG"
  export KUBECONFIG
fi

cg_info "Desplegando $VERSION en $ENV_NAME ($NAMESPACE)"
kubectl apply -f "$K8S_DIR/overlays/$ENV_NAME/namespace.yaml"
"$K8S_DIR/secrets.sh" "$ENV_NAME"

ECR_TOKEN=$(aws ecr get-login-password --region "$AWS_REGION")
# HU-14: the pull secret is built as a dockerconfigjson on stdin. --docker-password="$ECR_TOKEN" would put the token in the process list.
printf '{"auths":{"%s":{"username":"AWS","password":"%s","auth":"%s"}}}' "$ECR_REGISTRY" "$ECR_TOKEN" "$(printf 'AWS:%s' "$ECR_TOKEN" | base64 -w0)" \
  | kubectl -n "$NAMESPACE" create secret generic ecr-pull --type=kubernetes.io/dockerconfigjson \
      --from-file=.dockerconfigjson=/dev/stdin --dry-run=client -o yaml \
  | kubectl apply -f -
unset ECR_TOKEN

kubectl kustomize "$K8S_DIR/overlays/$ENV_NAME" \
  | sed -e "s|__REGISTRY__|$ECR_REGISTRY|g" -e "s|__TAG__|$VERSION|g" \
  | kubectl apply -f -

for sts in postgres zookeeper kafka redis neo4j openldap; do
  kubectl -n "$NAMESPACE" rollout status "statefulset/$sts" --timeout=600s
done
for dep in auth identity dashboard file form gateway notification promotion web; do
  kubectl -n "$NAMESPACE" rollout status "deployment/$dep" --timeout=600s
done

kubectl -n "$NAMESPACE" get pods,svc,ingress,hpa
