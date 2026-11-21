#!/usr/bin/env bash
set -Eeuo pipefail

ENV_NAME=${1:?uso: secrets.sh <dev|stage|prod>}
NAMESPACE=circleguard-$ENV_NAME
REGION=${AWS_REGION:-us-east-2}
PARAM=/circleguard/$ENV_NAME/app-secrets

generate() {
  printf 'POSTGRES_USER=circleguard\n'
  printf 'POSTGRES_PASSWORD=%s\n' "$(openssl rand -hex 16)"
  printf 'NEO4J_PASSWORD=%s\n' "$(openssl rand -hex 16)"
  printf 'LDAP_ADMIN_PASSWORD=%s\n' "$(openssl rand -hex 16)"
  printf 'CG_JWT_SECRET=%s\n' "$(openssl rand -hex 32)"
  printf 'CG_QR_SECRET=%s\n' "$(openssl rand -hex 32)"
  printf 'CG_VAULT_SECRET=%s\n' "$(openssl rand -hex 32)"
  printf 'CG_VAULT_SALT=%s\n' "$(openssl rand -hex 16)"
  printf 'CG_VAULT_HASH_SALT=%s\n' "$(openssl rand -hex 16)"
}

if VALUE=$(aws ssm get-parameter --region "$REGION" --name "$PARAM" --with-decryption --query Parameter.Value --output text 2>/dev/null); then
  echo "Secretos de $ENV_NAME leídos desde SSM"
else
  VALUE=$(generate)
  aws ssm put-parameter --region "$REGION" --name "$PARAM" --type SecureString --value "$VALUE" >/dev/null
  echo "Secretos de $ENV_NAME generados y guardados en SSM"
fi

printf '%s\n' "$VALUE" \
  | kubectl -n "$NAMESPACE" create secret generic circleguard-secrets --from-env-file=/dev/stdin --dry-run=client -o yaml \
  | kubectl apply -f -
