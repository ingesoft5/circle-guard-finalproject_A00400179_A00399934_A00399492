#!/usr/bin/env bash
# HU-15 · Gate of the OWASP ZAP baseline: counts the alerts of a ZAP JSON report by risk and applies the blocking threshold.
#
#   security/zap/evaluate-zap.sh <zap-report.json>
#
# Threshold: ZAP_BLOCK_RISK (security/policy.env): High (default), Medium or Low. Alerts of that risk or higher block.
# Exit code: 0 = nothing blocks; 1 = at least one alert reaches the threshold; 2 = the report is missing, is not a ZAP JSON report,
# or describes no scanned site (a scan that scanned nothing is never a pass).
# The report is never modified; every alert stays listed whatever the verdict.
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=security/policy.env
source "$ROOT_DIR/security/policy.env"

die2() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
report=${1:-}
[[ -n "$report" ]] || die2 "Uso: evaluate-zap.sh <zap-report.json>"
[[ -s "$report" ]] || die2 "el informe no existe o está vacío: $report"
grep -q '"@programName": *"ZAP"' "$report" || die2 "el informe no es un JSON de ZAP: $report"
grep -q '"@name"' "$report" || die2 "el informe no describe ningún sitio analizado: ZAP no alcanzó el objetivo."

case "$ZAP_BLOCK_RISK" in
  High) threshold=3 ;;
  Medium) threshold=2 ;;
  Low) threshold=1 ;;
  *) die2 "ZAP_BLOCK_RISK debe ser High, Medium o Low (recibido '$ZAP_BLOCK_RISK')." ;;
esac

# One line per alert: riskcode, instance count, plugin id, name. The keys appear in this order inside each alert.
alerts=$(grep -o -E '"(pluginid|alert|riskcode|count)": *"[^"]*"' "$report" | awk -F'"' '
  { key = $2; val = $4 }
  key == "pluginid" { id = val }
  key == "alert"    { name = val }
  key == "riskcode" { risk = val }
  key == "count"    { printf "%s\t%s\t%s\t%s\n", risk, val, id, name }
' | sort -t$'\t' -k1,1nr -k4,4)

count_risk() { { grep -c -E "^$1"$'\t' <<<"$alerts" || true; } ; }
high=$(count_risk 3); medium=$(count_risk 2); low=$(count_risk 1); info=$(count_risk 0)
blocking=0
while IFS=$'\t' read -r risk instances id name; do
  [[ -n "$risk" ]] || continue
  ((risk >= threshold)) && blocking=$((blocking + 1))
done <<<"$alerts"

label() { case "$1" in 3) echo High ;; 2) echo Medium ;; 1) echo Low ;; *) echo Informational ;; esac; }
printf 'ZAP baseline · umbral que bloquea: %s o superior\n' "$ZAP_BLOCK_RISK"
printf '%-14s %-10s %-8s %s\n' RIESGO INSTANCIAS PLUGIN ALERTA
while IFS=$'\t' read -r risk instances id name; do
  [[ -n "$risk" ]] || continue
  mark=""; ((risk >= threshold)) && mark="  <- bloquea"
  printf '%-14s %-10s %-8s %s%s\n' "$(label "$risk")" "$instances" "$id" "$name" "$mark"
done <<<"$alerts"
printf 'Alertas distintas: High=%s Medium=%s Low=%s Informational=%s\n' "$high" "$medium" "$low" "$info"

if ((blocking > 0)); then
  printf 'RESULT: FAIL · %s alerta(s) de riesgo %s o superior. La promoción debe detenerse.\n' "$blocking" "$ZAP_BLOCK_RISK"
  exit 1
fi
printf 'RESULT: PASS · ninguna alerta alcanza el umbral %s.\n' "$ZAP_BLOCK_RISK"
