#!/usr/bin/env bash
# HU-13: deploys the observability stack to the k3s cluster and collects the
# Kubernetes evidence. Requires kubectl and a working kubeconfig.
# Usage:
#   GRAFANA_ADMIN_PASSWORD='...' ./deploy/observability/k8s-evidence.sh
#   KUBECONFIG=/tmp/dev.kubeconfig ./deploy/observability/k8s-evidence.sh
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
OUT=${OUT_DIR:-"$ROOT_DIR/docs/evidencias/hu-13"}
mkdir -p "$OUT"

command -v kubectl >/dev/null 2>&1 || {
  printf 'Falta kubectl. Instale el cliente de Kubernetes.\n' >&2
  exit 1
}
if [[ -z "${KUBECONFIG:-}" && ! -f "${HOME}/.kube/config" ]]; then
  printf 'Falta el kubeconfig. Exporte KUBECONFIG o guarde ~/.kube/config.\n' >&2
  exit 1
fi

say() { printf '%s\n' "$*"; }

say "== HU-13: observabilidad en Kubernetes =="
kubectl apply -k "$ROOT_DIR/deploy/k8s/observability"

if [[ -n "${GRAFANA_ADMIN_PASSWORD:-}" ]]; then
  say "Creando/actualizando el secreto grafana-admin"
  kubectl -n observability create secret generic grafana-admin \
    --from-literal=admin-user="${GRAFANA_ADMIN_USER:-admin}" \
    --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n observability rollout restart deployment/grafana >/dev/null 2>&1 || true
else
  say "ADVERTENCIA: GRAFANA_ADMIN_PASSWORD no está definido; Grafana puede quedar en CrashLoop."
fi

for dep in prometheus alertmanager grafana jaeger loki; do
  say "Esperando deployment/$dep"
  kubectl -n observability rollout status "deployment/$dep" --timeout=180s || \
    say "ADVERTENCIA: deployment/$dep no quedó listo"
done

say "Estado del stack"
kubectl -n observability get pods,svc | tee "$OUT/10-k8s-observability.txt"

cat <<'EOF'

Port-forward para las capturas (una terminal por comando):
  kubectl -n observability port-forward svc/grafana 3000:3000
  kubectl -n observability port-forward svc/prometheus 9090:9090
  kubectl -n observability port-forward svc/alertmanager 9093:9093
  kubectl -n observability port-forward svc/jaeger 16686:16686
  kubectl -n observability port-forward svc/loki 3100:3100

Prometheus ya tiene targets estáticos para circleguard-dev; no hace falta
redesplegar la aplicación para las métricas. Para Loki, Promtail ya corre en
el clúster y lee los logs de los pods.
EOF
