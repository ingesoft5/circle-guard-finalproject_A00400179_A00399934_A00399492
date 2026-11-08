#!/usr/bin/env bash
# Computes the next semantic version from Git tags and Conventional Commits (HU-06).
# - feat: minor
# - fix/perf/other: patch
# - BREAKING CHANGE or type!: major
# Prints only the version (for example 1.2.0). If there are no commits after the
# last tag, prints the current version.
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
# shellcheck source=deploy/lib.sh
source "$ROOT_DIR/deploy/lib.sh"

# Only stable release tags count (vX.Y.Z); pre-releases are ignored.
LAST_TAG=$(git tag --list 'v[0-9]*' --sort=-v:refname 2>/dev/null \
  | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
  | head -n 1 || true)
if [[ -z "$LAST_TAG" ]]; then
  printf '0.1.0\n'
  exit 0
fi

BASE=${LAST_TAG#v}
if [[ ! "$BASE" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  cg_die "El último tag $LAST_TAG no es semver (se espera vMAJOR.MINOR.PATCH)."
fi

COUNT=$(git rev-list --count "$LAST_TAG..HEAD")
if [[ "$COUNT" == "0" ]]; then
  printf '%s\n' "$BASE"
  exit 0
fi

LOG=$(git log --pretty=format:'%s%n%b' "$LAST_TAG..HEAD")
MAJOR=${BASE%%.*}
REST=${BASE#*.}
MINOR=${REST%%.*}
PATCH=${REST#*.}

if printf '%s\n' "$LOG" | grep -qE 'BREAKING CHANGE|^[A-Za-z]+(\(.+\))?!:'; then
  MAJOR=$((MAJOR + 1))
  MINOR=0
  PATCH=0
elif printf '%s\n' "$LOG" | grep -qE '^feat(\(.+\))?:'; then
  MINOR=$((MINOR + 1))
  PATCH=0
else
  PATCH=$((PATCH + 1))
fi

printf '%s.%s.%s\n' "$MAJOR" "$MINOR" "$PATCH"
