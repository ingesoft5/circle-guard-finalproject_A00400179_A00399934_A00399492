#!/usr/bin/env bash
set -euo pipefail

PATTERN='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9._/-]+\))?!?: [^ ].{0,71}$'

validate_subject() {
  local subject="$1"
  if [[ "$subject" =~ ^(Merge|Revert\ \") ]]; then
    return 0
  fi
  if [[ "$subject" =~ $PATTERN ]]; then
    return 0
  fi
  echo "INVALID: $subject" >&2
  return 1
}

usage() {
  echo "uso: $0 --file <archivo-mensaje> | <rango-git>" >&2
  exit 2
}

[[ $# -eq 1 || $# -eq 2 ]] || usage

failed=0

if [[ "$1" == "--file" ]]; then
  [[ $# -eq 2 ]] || usage
  subject="$(head -n 1 "$2")"
  validate_subject "$subject" || failed=1
else
  while IFS= read -r subject; do
    validate_subject "$subject" || failed=1
  done < <(git log --no-merges --format=%s "$1")
fi

if [[ $failed -ne 0 ]]; then
  echo "Formato: <tipo>(<alcance>)?: <descripcion>" >&2
  echo "Tipos: feat fix docs style refactor perf test build ci chore revert" >&2
  exit 1
fi

echo "OK: Conventional Commits"
