#!/usr/bin/env bash
# Generates release notes from Git commits and updates CHANGELOG.md (HU-07).
# Usage: ./deploy/release-notes.sh 1.0.0
# Uses the tag v<version> and the previous v* tag. PR references "(#123)" are
# converted to links using the GitHub repository URL.
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
# shellcheck source=deploy/lib.sh
source "$ROOT_DIR/deploy/lib.sh"

VERSION=${1:-}
cg_validate_semver "$VERSION"
TAG="v$VERSION"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || cg_die "No existe el tag $TAG."

PREV=$(git describe --tags --abbrev=0 --match 'v[0-9]*' "$TAG^" 2>/dev/null || true)
RANGE="${PREV:+$PREV..}$TAG"
LOG=$(git log --pretty=format:'%s' "$RANGE")
TAG_COMMIT=$(git rev-parse --short "$TAG^{commit}")
DATE=$(date -u +%Y-%m-%d)
OUT_DIR="$ROOT_DIR/docs/release-notes"
OUT="$OUT_DIR/v$VERSION.md"
mkdir -p "$OUT_DIR"

section() {
  local title=$1 body=$2
  [[ -n "$body" ]] || return 0
  printf '## %s\n\n' "$title"
  printf '%s\n' "$body" \
    | sed -E 's/^(feat|fix|perf|docs|chore|refactor|test)(\([^)]+\))?: //' \
    | sed -E "s|\(#([0-9]+)\)|([#\1](${CG_GITHUB_URL}/pull/\1))|g" \
    | sed 's/^/- /'
  printf '\n'
}

FEATURES=$(printf '%s\n' "$LOG" | grep -E '^feat(\(.+\))?:' || true)
FIXES=$(printf '%s\n' "$LOG" | grep -E '^fix(\(.+\))?:' || true)
PERF=$(printf '%s\n' "$LOG" | grep -E '^perf(\(.+\))?:' || true)
OTHER=$(printf '%s\n' "$LOG" | grep -Ev '^(feat|fix|perf)(\(.+\))?:' || true)

{
  printf '# Release v%s\n\n' "$VERSION"
  printf -- '- Fecha: %s\n' "$DATE"
  printf -- '- Tag: `%s`\n' "$TAG"
  printf -- '- Commit: `%s`\n' "$TAG_COMMIT"
  if [[ -n "$PREV" ]]; then printf -- '- Desde: `%s`\n' "$PREV"; fi
  printf '\n'
  section 'Features' "$FEATURES"
  section 'Fixes' "$FIXES"
  section 'Performance' "$PERF"
  section 'Otros' "$OTHER"
} > "$OUT"

CHANGELOG="$ROOT_DIR/CHANGELOG.md"
if [[ -f "$CHANGELOG" ]] && grep -Fq "## [v$VERSION]" "$CHANGELOG"; then
  cg_info "CHANGELOG.md ya contiene v$VERSION; no se duplica."
else
  TMP=$(mktemp)
  if [[ -f "$CHANGELOG" ]] && grep -q '<!-- releases -->' "$CHANGELOG"; then
    # Insert after the marker (the marker sits after Unreleased and before the releases).
    awk -v notes="$OUT" -v version="$VERSION" -v date="$DATE" '
      { print }
      /<!-- releases -->/ {
        print ""
        print "## [v" version "] - " date
        print ""
        n = 0
        while ((getline line < notes) > 0) {
          n++
          if (n > 2) print line
        }
        close(notes)
        print ""
      }
    ' "$CHANGELOG" > "$TMP"
  elif [[ -f "$CHANGELOG" ]]; then
    {
      head -n 2 "$CHANGELOG"
      printf '\n## [v%s] - %s\n\n' "$VERSION" "$DATE"
      tail -n +3 "$OUT"
      printf '\n'
      tail -n +3 "$CHANGELOG"
    } > "$TMP"
  else
    {
      printf '# Changelog\n\n'
      printf 'Todas las versiones notables de CircleGuard. Formato basado en Keep a Changelog y Conventional Commits.\n'
      printf '\n<!-- releases -->\n'
      printf '\n## [v%s] - %s\n\n' "$VERSION" "$DATE"
      tail -n +3 "$OUT"
    } > "$TMP"
  fi
  mv "$TMP" "$CHANGELOG"
fi

cg_info "Release notes: $OUT"
cg_info "CHANGELOG actualizado: $CHANGELOG"
