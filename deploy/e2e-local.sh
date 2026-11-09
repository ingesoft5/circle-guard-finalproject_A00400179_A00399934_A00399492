#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PORT=${E2E_PORT:-3000}

command -v node >/dev/null 2>&1 || { echo "ERROR: node no está disponible en este agente." >&2; exit 1; }
command -v npm >/dev/null 2>&1 || { echo "ERROR: npm no está disponible en este agente." >&2; exit 1; }

export CI=1
export EXPO_NO_TELEMETRY=1

cd "$ROOT_DIR/mobile"
npm ci --no-audit --no-fund
npx expo export --platform web --output-dir dist

node "$ROOT_DIR/deploy/serve-web.mjs" "$ROOT_DIR/mobile/dist" "$PORT" &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

for _ in $(seq 1 30); do
  if node -e "fetch('http://127.0.0.1:${PORT}/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"; then
    break
  fi
  sleep 1
done

cd "$ROOT_DIR/tests/e2e-playwright"
npm ci --no-audit --no-fund
npx playwright install chromium
E2E_BASE_URL="http://127.0.0.1:${PORT}" npx playwright test
