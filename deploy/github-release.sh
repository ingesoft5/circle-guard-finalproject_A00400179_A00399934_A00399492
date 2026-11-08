#!/usr/bin/env bash
# Publishes the generated release notes as a GitHub Release (HU-07).
# Usage: GITHUB_TOKEN=... ./deploy/github-release.sh 0.2.0
# The token is read only from the environment and is never printed.
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
# shellcheck source=deploy/lib.sh
source "$ROOT_DIR/deploy/lib.sh"

VERSION=${1:-}
cg_validate_semver "$VERSION"
TAG="v$VERSION"
NOTES="$ROOT_DIR/docs/release-notes/v$VERSION.md"
[[ -f "$NOTES" ]] || cg_die "No existen $NOTES; ejecute deploy/release-notes.sh $VERSION."
[[ -n "${GITHUB_TOKEN:-}" ]] || cg_die "Falta GITHUB_TOKEN (credencial github-token de Jenkins)."

REPO=${CG_GITHUB_URL#https://github.com/}
REPO=${REPO%.git}
[[ "$REPO" == */* ]] || cg_die "No se pudo derivar owner/repo de CG_GITHUB_URL=$CG_GITHUB_URL."
API="https://api.github.com/repos/$REPO/releases"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
PAYLOAD="$TMP_DIR/release.json"
RESP="$TMP_DIR/response.json"
EXISTING="$TMP_DIR/existing.json"

node - "$TAG" "$NOTES" > "$PAYLOAD" <<'NODE'
const fs = require('fs');
const [tag, notesPath] = process.argv.slice(2);
const body = fs.readFileSync(notesPath, 'utf8');
process.stdout.write(JSON.stringify({
  tag_name: tag,
  name: `CircleGuard ${tag}`,
  body,
  draft: false,
  prerelease: false,
}));
NODE

CODE=$(curl -sS -o "$EXISTING" -w '%{http_code}' \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H 'Accept: application/vnd.github+json' \
  "$API/tags/$TAG" || true)
RELEASE_ID=""
if [[ "$CODE" == "200" ]]; then
  RELEASE_ID=$(node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const r=JSON.parse(s);if(r.id)process.stdout.write(String(r.id))}catch(e){}})' < "$EXISTING")
fi

if [[ -n "$RELEASE_ID" ]]; then
  CODE=$(curl -sS -o "$RESP" -w '%{http_code}' -X PATCH \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H 'Accept: application/vnd.github+json' \
    -H 'Content-Type: application/json' \
    --data-binary "@$PAYLOAD" \
    "$API/$RELEASE_ID" || true)
  ACTION="actualizado"
else
  CODE=$(curl -sS -o "$RESP" -w '%{http_code}' -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H 'Accept: application/vnd.github+json' \
    -H 'Content-Type: application/json' \
    --data-binary "@$PAYLOAD" \
    "$API" || true)
  ACTION="creado"
fi

[[ "$CODE" == "200" || "$CODE" == "201" ]] \
  || cg_die "GitHub release falló (HTTP $CODE): $(cat "$RESP")"
URL=$(node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const r=JSON.parse(s);if(r.html_url)process.stdout.write(r.html_url)}catch(e){}})' < "$RESP")
cg_info "GitHub release $ACTION: $URL"
