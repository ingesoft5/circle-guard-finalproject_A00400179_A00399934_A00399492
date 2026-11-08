#!/usr/bin/env bash
# Records the version deployed to an environment (HU-06 traceability).
# Usage: ./deploy/record-release.sh <dev|stage|prod> <semver> [deploy|rollback|promote|hotfix] [actor]
# Writes deploy/releases/<env>.json (latest) and deploy/releases/history.tsv (append-only).
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
# shellcheck source=deploy/lib.sh
source "$ROOT_DIR/deploy/lib.sh"

ENV_NAME=${1:-}
VERSION=${2:-}
EVENT=${3:-deploy}
ACTOR=${4:-${USER:-jenkins}}

cg_validate_env "$ENV_NAME"
cg_validate_semver "$VERSION"
case "$EVENT" in
  deploy|rollback|promote|hotfix) ;;
  *) cg_die "Evento inválido '$EVENT'. Use deploy, rollback, promote o hotfix." ;;
esac
ACTOR=$(printf '%s' "$ACTOR" | tr -cd 'A-Za-z0-9_.@-')
[[ -n "$ACTOR" ]] || ACTOR=unknown

COMMIT=$(cg_short_commit)
TIMESTAMP=$(cg_utc_now)
RELEASES_DIR="$ROOT_DIR/deploy/releases"
mkdir -p "$RELEASES_DIR"
JSON="$RELEASES_DIR/$ENV_NAME.json"
HISTORY="$RELEASES_DIR/history.tsv"

cat > "$JSON" <<EOF
{
  "environment": "$ENV_NAME",
  "version": "$VERSION",
  "commit": "$COMMIT",
  "deployed_at": "$TIMESTAMP",
  "deployed_by": "$ACTOR",
  "event": "$EVENT"
}
EOF

if [[ ! -f "$HISTORY" ]]; then
  printf 'timestamp\tenvironment\tversion\tcommit\tdeployed_by\tevent\n' > "$HISTORY"
fi
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$TIMESTAMP" "$ENV_NAME" "$VERSION" "$COMMIT" "$ACTOR" "$EVENT" >> "$HISTORY"

PERSIST_DIR="$CG_RELEASES_DIR"
if [[ "$PERSIST_DIR" != "$RELEASES_DIR" ]]; then
  mkdir -p "$PERSIST_DIR"
  cp "$JSON" "$PERSIST_DIR/$ENV_NAME.json"
  PERSIST_HISTORY="$PERSIST_DIR/history.tsv"
  if [[ ! -f "$PERSIST_HISTORY" ]]; then
    printf 'timestamp\tenvironment\tversion\tcommit\tdeployed_by\tevent\n' > "$PERSIST_HISTORY"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$TIMESTAMP" "$ENV_NAME" "$VERSION" "$COMMIT" "$ACTOR" "$EVENT" >> "$PERSIST_HISTORY"
fi

cg_info "Trazabilidad actualizada: $JSON"
cg_info "Copia persistente:        $PERSIST_DIR/$ENV_NAME.json"
