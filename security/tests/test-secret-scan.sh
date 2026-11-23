#!/usr/bin/env bash
# HU-14 · Tests of security/scan-secrets-ci.sh in throwaway Git repositories (needs Docker; no network after the image is cached).
# The "secrets" below are obviously fictitious strings written only inside temporary directories.
# Usage: security/tests/test-secret-scan.sh        Exit code: 0 = every case behaved as expected.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PASSED=0 FAILED=0
# The variable name is assembled at run time so that this file never contains a literal credential assignment
# (the project scanner would, rightly, flag it as ACTIVO).
VAR_NAME="POSTGRES_PASS""WORD"

new_repo() { # new_repo <name>: a Git repository with the scanner, the policy and the project ruleset
  local d="$WORK/$1"
  mkdir -p "$d/security" && cd "$d" || exit 1
  git init -q . && git config user.email t@example.invalid && git config user.name t
  cp "$ROOT/security/scan-secrets-ci.sh" "$ROOT/security/policy.env" security/
  cp "$ROOT/.gitleaks.toml" .
  printf 'security/reports/\n.env\n' > .gitignore
  echo "# demo" > README.md
}

check() { # check <description> <expected exit code> <expected text>
  local out rc
  out=$(bash security/scan-secrets-ci.sh 2>&1); rc=$?
  if [[ "$rc" == "$2" && "$out" == *"$3"* ]]; then
    printf 'PASS  %s (exit %s)\n' "$1" "$rc"; PASSED=$((PASSED + 1))
  else
    printf 'FAIL  %s: expected exit %s with "%s", got exit %s\n----\n%s\n----\n' "$1" "$2" "$3" "$rc" "$out"; FAILED=$((FAILED + 1))
  fi
}

new_repo clean
check "a repository without secrets passes" 0 "PASS"

new_repo literal
mkdir -p config && printf 'spring:\n  datasource:\n    password: "FAKE-literal-credential-0000"\n' > config/application.yml
check "a literal password in a YAML file fails the gate" 1 "ACTIVO   "

new_repo envfile
printf '%s=FAKE-env-credential-0000\n' "$VAR_NAME" > deploy.env
check "a literal credential variable in an env-style file fails the gate" 1 "FAIL"

new_repo testvalue
mkdir -p svc/src/test/resources && printf 'spring:\n  datasource:\n    password: "FAKE-test-fixture-0000"\n' > svc/src/test/resources/application.yml
check "the same value under src/test is classified PRUEBA and does not fail" 0 "PRUEBA"

new_repo reference
mkdir -p config && printf 'spring:\n  datasource:\n    password: ${POSTGRES_PASSWORD}\n' > config/application.yml
check "a reference to an environment variable is not a secret" 0 "PASS"

new_repo default
printf 'services:\n  grafana:\n    environment:\n      %s: ${GRAFANA_X:-FAKE-default-0000}\n' "$VAR_NAME" > compose.yml
check "a credential variable with a default value inside \${VAR:-...} fails the gate" 1 "circleguard-env-default-credential"

new_repo required
printf 'services:\n  grafana:\n    environment:\n      %s: ${GRAFANA_X:?Define GRAFANA_X}\n' "$VAR_NAME" > compose.yml
check "a required variable without default (\${VAR:?...}) passes" 0 "PASS"

new_repo ignored
printf '%s=FAKE-ignored-credential-0000\n' "$VAR_NAME" > .env
check "a git-ignored local .env file is out of scope" 0 "PASS"

new_repo migration
mkdir -p svc/src/main/resources/db/migration && printf -- "-- BCrypt hash for the password is 'FAKE-seed-0000'\nSELECT 1;\n" > svc/src/main/resources/db/migration/V2__seed.sql
check "an immutable V2/V3 migration is classified RESIDUAL" 0 "RESIDUAL"

printf '\n%s passed, %s failed\n' "$PASSED" "$FAILED"
((FAILED == 0))
