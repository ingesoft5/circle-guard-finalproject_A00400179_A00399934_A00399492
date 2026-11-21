#!/usr/bin/env bash
# HU-13: collects textual evidence from a running observability stack.
# It does not replace the dashboard screenshots; it records the raw responses
# used to justify them. Usage: ./deploy/observability/capture-evidence.sh [host] [outdir]
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
HOST=${1:-localhost}
OUT=${2:-"$ROOT_DIR/docs/evidencias/hu-13"}
PROM_URL=${PROM_URL:-http://localhost:9090}
ALERTMANAGER_URL=${ALERTMANAGER_URL:-http://localhost:9093}
JAEGER_URL=${JAEGER_URL:-http://localhost:16686}
LOKI_URL=${LOKI_URL:-http://localhost:3100}

command -v curl >/dev/null 2>&1 || { printf 'Falta curl\n' >&2; exit 1; }
mkdir -p "$OUT"

say() { printf '%s\n' "$*"; }
fetch() {
  local url=$1 out=$2
  if curl -fsS "$url" -o "$out"; then
    say "  OK  $out"
  else
    say "  ADVERTENCIA: no se pudo consultar $url"
  fi
}

say "== HU-13: captura de evidencia (host=$HOST) =="
say "Salida: $OUT"

say "1/5 Endpoints /actuator/prometheus de los 8 servicios"
"$ROOT_DIR/deploy/observability/check-metrics.sh" "$HOST" | tee "$OUT/09-check-metrics.txt" || \
  say "  ADVERTENCIA: algun servicio no respondio; revisar 09-check-metrics.txt"

say "2/5 Targets de Prometheus"
fetch "$PROM_URL/api/v1/targets" "$OUT/10-prometheus-targets.json"
if command -v jq >/dev/null 2>&1 && [[ -s "$OUT/10-prometheus-targets.json" ]]; then
  jq -r '.data.activeTargets[] | [.scrapeUrl, .health, (.lastError // "")] | @tsv' \
    "$OUT/10-prometheus-targets.json" > "$OUT/10-prometheus-targets.txt"
fi

say "3/5 Alertas de Alertmanager"
fetch "$ALERTMANAGER_URL/api/v2/alerts" "$OUT/11-alertmanager-alerts.json"
if command -v jq >/dev/null 2>&1 && [[ -s "$OUT/11-alertmanager-alerts.json" ]]; then
  jq -r '.[] | [.labels.alertname, .labels.severity, .status.state, (.annotations.summary // "")] | @tsv' \
    "$OUT/11-alertmanager-alerts.json" > "$OUT/11-alertmanager-alerts.txt"
fi

say "4/5 Servicios y trazas de Jaeger"
fetch "$JAEGER_URL/api/services" "$OUT/12-jaeger-services.json"
fetch "$JAEGER_URL/api/traces?service=circleguard-form-service&limit=20" "$OUT/12-jaeger-traces.json"

say "5/5 Errores recientes en Loki"
if curl -fsS -G "$LOKI_URL/loki/api/v1/query" \
  --data-urlencode 'query={service=~"circleguard-.*"} |= "ERROR"' \
  --data-urlencode 'limit=200' \
  -o "$OUT/13-loki-errors.json"; then
  say "  OK  $OUT/13-loki-errors.json"
else
  say "  ADVERTENCIA: no se pudo consultar Loki"
fi

cat <<'EOF'

Captura automatica terminada. Faltan las capturas manuales:
  02-grafana-servicio.png    Dashboard tecnico con trafico
  03-grafana-negocio.png     Dashboard de negocio con trafico
  04-alertmanager-firing.png Alerta en firing
  05-jaeger-traza.png        Traza con los cuatro spans
  06-kafka-headers.txt       traceId en los headers de Kafka
  07-loki-consulta.png       Consulta por traceId y severidad
  08-incidente.md            Ejecutar la falla de identity
EOF
