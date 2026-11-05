#!/usr/bin/env bash
# Sends a deployment notification to Discord or Slack (HU-07).
# Usage: ./deploy/notify.sh <success|failure|rollback|unstable|info> <env> <version> [message]
# The webhook URL is read from DISCORD_WEBHOOK_URL or SLACK_WEBHOOK_URL and is
# never printed. If no webhook is configured, the script exits 0 (local runs).
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
# shellcheck source=deploy/lib.sh
source "$ROOT_DIR/deploy/lib.sh"

STATUS=${1:-info}
ENV_NAME=${2:-ci}
VERSION=${3:-unknown}
MESSAGE=${4:-}

case "$STATUS" in
  success|failure|rollback|unstable|info) ;;
  *) STATUS=info ;;
esac

if [[ -n "${DISCORD_WEBHOOK_URL:-}" ]]; then
  URL=$DISCORD_WEBHOOK_URL
  PAYLOAD_KEY=content
elif [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
  URL=$SLACK_WEBHOOK_URL
  PAYLOAD_KEY=text
else
  cg_info "Notificación omitida: defina DISCORD_WEBHOOK_URL o SLACK_WEBHOOK_URL."
  exit 0
fi

TEXT="[CircleGuard] ${STATUS} · ${ENV_NAME} · ${VERSION}"
[[ -n "$MESSAGE" ]] && TEXT="$TEXT · $MESSAGE"
[[ -n "${BUILD_URL:-}" ]] && TEXT="$TEXT · $BUILD_URL"
ESCAPED=$(printf '%s' "$TEXT" | tr '\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')
PAYLOAD=$(printf '{"%s":"%s"}' "$PAYLOAD_KEY" "$ESCAPED")

if ! curl -fsS -H 'Content-Type: application/json' --data "$PAYLOAD" "$URL" >/dev/null; then
  cg_info "ADVERTENCIA: no se pudo enviar la notificación; el despliegue no se marca como fallido."
  exit 0
fi
cg_info "Notificación enviada."
