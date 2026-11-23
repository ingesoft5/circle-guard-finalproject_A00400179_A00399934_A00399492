#!/usr/bin/env bash
# Records the version deployed to an environment (HU-06 traceability).
# Usage: ./deploy/record-release.sh <dev|stage|prod> <semver> [deploy|rollback|promote|hotfix] [actor]
# Writes deploy/releases/<env>.json (latest) and deploy/releases/history.tsv (append-only).
# D-30 (HU-16): optional fields via environment:
#   RESULT=success|failure|rolled_back|unknown
#   APPROVED_BY="nombre"  APPROVAL_REF="url-o-id"  IMAGE_DIGEST="sha256:..."
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

# D-30: campos ampliados del registro de cambios. Son opcionales para no romper las llamadas
# existentes (deploy.sh los deja vacíos) y los completa el pipeline o el operador.
RESULT=${RESULT:-success}
APPROVED_BY=${APPROVED_BY:-}
APPROVAL_REF=${APPROVAL_REF:-}
IMAGE_DIGEST=${IMAGE_DIGEST:-}
case "$RESULT" in
  success|failure|rolled_back|unknown) ;;
  *) RESULT=unknown ;;
esac
json_escape() { printf '%s' "$1" | tr -d '\r\n' | sed 's/\\/\\\\/g; s/"/\\"/g'; }
tsv_clean() { printf '%s' "$1" | tr -d '\t\r\n'; }
APPROVED_BY_JSON=$(json_escape "$APPROVED_BY")
APPROVAL_REF_JSON=$(json_escape "$APPROVAL_REF")
IMAGE_DIGEST_JSON=$(json_escape "$IMAGE_DIGEST")
APPROVED_BY_TSV=$(tsv_clean "$APPROVED_BY")
APPROVAL_REF_TSV=$(tsv_clean "$APPROVAL_REF")

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
  "event": "$EVENT",
  "result": "$RESULT",
  "approved_by": "$APPROVED_BY_JSON",
  "approval_ref": "$APPROVAL_REF_JSON",
  "image_digest": "$IMAGE_DIGEST_JSON"
}
EOF

HISTORY_HEADER=$'timestamp\tenvironment\tversion\tcommit\tdeployed_by\tevent\tresult\tapproved_by\tapproval_ref'
ensure_history() {
  local file=$1
  if [[ ! -f "$file" ]]; then
    printf '%s\n' "$HISTORY_HEADER" > "$file"
  elif [[ "$(head -n1 "$file")" != "$HISTORY_HEADER" ]]; then
    # Migra un historial de 6 columnas al esquema D-30 sin perder filas.
    awk -F'\t' 'BEGIN{OFS="\t"} NR==1{print "timestamp","environment","version","commit","deployed_by","event","result","approved_by","approval_ref"; next} {print $0,"","",""}' \
      "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  fi
}

ensure_history "$HISTORY"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$TIMESTAMP" "$ENV_NAME" "$VERSION" "$COMMIT" "$ACTOR" "$EVENT" "$RESULT" "$APPROVED_BY_TSV" "$APPROVAL_REF_TSV" \
  >> "$HISTORY"

PERSIST_DIR="$CG_RELEASES_DIR"
if [[ "$PERSIST_DIR" != "$RELEASES_DIR" ]]; then
  mkdir -p "$PERSIST_DIR"
  cp "$JSON" "$PERSIST_DIR/$ENV_NAME.json"
  PERSIST_HISTORY="$PERSIST_DIR/history.tsv"
  ensure_history "$PERSIST_HISTORY"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$TIMESTAMP" "$ENV_NAME" "$VERSION" "$COMMIT" "$ACTOR" "$EVENT" "$RESULT" "$APPROVED_BY_TSV" "$APPROVAL_REF_TSV" \
    >> "$PERSIST_HISTORY"
fi

cg_info "Trazabilidad actualizada: $JSON"
cg_info "Copia persistente:        $PERSIST_DIR/$ENV_NAME.json"
