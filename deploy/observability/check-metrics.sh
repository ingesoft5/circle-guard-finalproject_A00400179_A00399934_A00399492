#!/usr/bin/env bash
# HU-13 smoke check: every CircleGuard service must expose Prometheus metrics.
# Usage: ./deploy/observability/check-metrics.sh [host]
set -Eeuo pipefail

HOST=${1:-localhost}
SERVICES=(
  "auth:8180"
  "identity:8083"
  "form:8086"
  "promotion:8088"
  "notification:8082"
  "gateway:8087"
  "dashboard:8084"
  "file:8085"
)

fail=0
for entry in "${SERVICES[@]}"; do
  name=${entry%%:*}
  port=${entry##*:}
  url="http://${HOST}:${port}/actuator/prometheus"
  body=$(mktemp)
  code=$(curl -sS -o "$body" -w '%{http_code}' "$url" 2>/dev/null || true)
  if [[ "$code" == "200" ]] && grep -q '^jvm_' "$body"; then
    printf 'PASS  %-14s %s\n' "$name" "$url"
  else
    printf 'FAIL  %-14s %s (HTTP %s)\n' "$name" "$url" "${code:-no-response}"
    fail=1
  fi
  rm -f "$body"
done

if [[ "$fail" -ne 0 ]]; then
  echo "One or more services do not expose /actuator/prometheus." >&2
fi
exit "$fail"
