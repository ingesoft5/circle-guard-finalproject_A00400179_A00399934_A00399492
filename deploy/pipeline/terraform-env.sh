#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$ROOT_DIR/deploy/lib.sh"

ENV_NAME=${1:?uso: terraform-env.sh <dev|stage|prod> <plan|apply>}
ACTION=${2:?uso: terraform-env.sh <dev|stage|prod> <plan|apply>}
cg_validate_env "$ENV_NAME"
case "$ACTION" in plan|apply) ;; *) cg_die "Acción inválida: $ACTION" ;; esac
: "${TF_VAR_admin_cidr:?Defina ADMIN_CIDR con formato a.b.c.d/32}"

REPORT_DIR=$ROOT_DIR/deploy/pipeline-reports
mkdir -p "$REPORT_DIR"
cd "$ROOT_DIR/infra/terraform/envs/$ENV_NAME"

if [[ "$ACTION" == plan ]]; then
  terraform fmt -check -recursive "$ROOT_DIR/infra/terraform"
  terraform init -input=false
  terraform validate
  terraform plan -input=false -lock-timeout=60s -out=ci.tfplan
  terraform show -no-color ci.tfplan > "$REPORT_DIR/terraform-$ENV_NAME-plan.txt"
  if grep -q "must be replaced" "$REPORT_DIR/terraform-$ENV_NAME-plan.txt"; then
    cg_info "AVISO: el plan de $ENV_NAME reemplaza recursos"
  fi
  exit 0
fi

[[ -f ci.tfplan ]] || cg_die "No existe el plan guardado de $ENV_NAME. Ejecute plan primero."
terraform show -no-color ci.tfplan > "$REPORT_DIR/terraform-$ENV_NAME-pre-apply.txt"
if grep -q "must be replaced" "$REPORT_DIR/terraform-$ENV_NAME-pre-apply.txt"; then
  cg_die "El plan de $ENV_NAME reemplaza recursos. Apply cancelado."
fi
terraform apply -input=false -lock-timeout=60s ci.tfplan | tee "$REPORT_DIR/terraform-$ENV_NAME-apply.txt"
