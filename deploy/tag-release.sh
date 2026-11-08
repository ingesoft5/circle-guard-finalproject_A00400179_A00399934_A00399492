#!/usr/bin/env bash
# Creates and publishes the annotated Git tag v<version> for a release (HU-06).
# Usage: ./deploy/tag-release.sh 1.0.0
# Jenkins must provide Git credentials (SSH key or credential helper); the script
# never receives or prints a token.
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
# shellcheck source=deploy/lib.sh
source "$ROOT_DIR/deploy/lib.sh"

VERSION=${1:-}
cg_validate_semver "$VERSION"
TAG="v$VERSION"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  EXISTING=$(git rev-list -n 1 "$TAG")
  HEAD_SHA=$(git rev-parse HEAD)
  if [[ "$EXISTING" == "$HEAD_SHA" ]]; then
    cg_info "El tag $TAG ya existe en HEAD; no se crea de nuevo."
    exit 0
  fi
  cg_die "El tag $TAG ya existe en otro commit ($EXISTING)."
fi

git config user.name "${GIT_AUTHOR_NAME:-CircleGuard CI}"
git config user.email "${GIT_AUTHOR_EMAIL:-ci@circleguard.local}"
git tag -a "$TAG" -m "Release $VERSION"

case "${PUSH_TAG:-1}" in
  0|false|False|FALSE|no|No|NO)
    cg_info "PUSH_TAG=0: tag $TAG creado localmente; no se publica en origin."
    exit 0
    ;;
esac

REMOTE=$(git remote get-url origin)
PUSH_URL=$REMOTE
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  if [[ -n "${CG_GITHUB_URL:-}" ]]; then
    PUSH_URL="${CG_GITHUB_URL%.git}.git"
  elif [[ "$REMOTE" == git@github.com:* ]]; then
    PUSH_URL="https://github.com/${REMOTE#git@github.com:}"
  fi
  # Pass the token through the environment, not through the command line.
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0=http.extraHeader
  export GIT_CONFIG_VALUE_0="AUTHORIZATION: bearer $GITHUB_TOKEN"
  git push "$PUSH_URL" "$TAG"
  unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
else
  git push origin "$TAG"
fi
cg_info "Tag $TAG creado y publicado."
