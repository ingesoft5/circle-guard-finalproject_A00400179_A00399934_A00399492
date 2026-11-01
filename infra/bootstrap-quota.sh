#!/usr/bin/env bash
# HU-01 · EC2 vCPU quota "Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances"
# (L-1216C47A) in the HU-01 region. The six servers need 12 vCPU running at the same time.
#   --plan (default)           current value, AWS default and previous requests (read-only)
#   --apply --approve quota    submits ONE increase request to QUOTA_VCPU_TARGET; AWS reviews it
# A quota request is free, creates no resources and does not change the billing plan. Uses the
# bootstrap session (infra/aws-session.sh login bootstrap).

# shellcheck source=bootstrap/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/aws.sh
source "$INFRA_DIR/bootstrap/lib/aws.sh"

usage() {
  cat <<'EOF'
Uso: infra/bootstrap-quota.sh [--plan | --apply --approve quota]
  --plan                   (por defecto) cuota actual, valor por defecto y solicitudes previas
  --apply --approve quota  envía una solicitud de aumento a QUOTA_VCPU_TARGET (sin costo)
EOF
}

QUOTA=(--service-code ec2 --quota-code L-1216C47A)

cg_parse_flags "$@"
cg_load_config
((${#CG_ARGS[@]} == 0)) || die "opción desconocida: ${CG_ARGS[0]}"
if is_apply && [[ ",$CG_APPROVED," != *",quota,"* ]]; then die "Enviar la solicitud requiere --apply --approve quota."; fi
cg_start_log bootstrap-quota
cg_aws_use bootstrap
cg_aws_identity
current=$(aws_ service-quotas get-service-quota "${QUOTA[@]}" --query 'Quota.[Value,Adjustable]' --output text)
read -r value adjustable <<<"$current"
info "cuota actual en $AWS_REGION: $value vCPU (ajustable: $adjustable) · valor por defecto de AWS: $(aws_ service-quotas \
  get-aws-default-service-quota "${QUOTA[@]}" --query Quota.Value --output text) · objetivo: $QUOTA_VCPU_TARGET"
requests=$(aws_ service-quotas list-requested-service-quota-change-history-by-quota "${QUOTA[@]}" \
  --query 'RequestedQuotas[].[Created,DesiredValue,Status]' --output text)
if [[ -n "$requests" ]]; then
  while read -r line; do info "  solicitud previa: $line"; done <<<"$requests"
fi

if awk -v v="$value" -v t="$QUOTA_VCPU_TARGET" 'BEGIN { exit !(v >= t) }'; then
  unchanged "la cuota ya es de $value vCPU"
elif grep -qE 'PENDING|CASE_OPENED' <<<"$requests"; then
  unchanged "ya hay una solicitud en curso: no se envía otra"
elif [[ "$adjustable" != True ]]; then
  die "La cuota no es ajustable en esta cuenta."
elif is_apply; then
  aws_ service-quotas request-service-quota-increase "${QUOTA[@]}" --desired-value "$QUOTA_VCPU_TARGET" \
    --query 'RequestedQuota.[Id,Status]' --output text | while read -r id status; do
    created "solicitud de aumento a $QUOTA_VCPU_TARGET vCPU enviada (id $id, estado $status); AWS la revisa"
  done
else
  planned "solicitar el aumento de $value a $QUOTA_VCPU_TARGET vCPU (sin costo; requiere --apply --approve quota)"
fi
cg_summary bootstrap-quota
