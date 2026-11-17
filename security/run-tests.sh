#!/usr/bin/env bash
# HU-14 · Runs every test of the security tooling and prints one line per suite.
#
#   security/run-tests.sh              offline suites only (no Docker, no network): gate, Jenkins audit, create-secrets, RBAC
#   security/run-tests.sh --docker     adds the suites that start containers: secret scanner and TLS (needs Docker; images are cached after the first run)
#
# These tests check the TOOLS with fictitious data. They do not scan the project: for that run security/scan-secrets-ci.sh,
# security/scan-dependencies.sh and security/scan-images.sh. The live Jenkins RBAC check (security/jenkins/validate-rbac-live.sh) is not
# included because it downloads plugins and takes minutes; run it by hand.
# Exit code: 0 = every suite passed; 1 = at least one failed.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DOCKER=0; [[ "${1:-}" == --docker ]] && DOCKER=1

suites=(test-gate.sh test-jenkins-audit.sh test-create-secrets.sh test-rbac.sh)
((DOCKER)) && suites+=(test-secret-scan.sh test-tls.sh)

failed=0
printf '%-26s %s\n' SUITE RESULT
for s in "${suites[@]}"; do
  out=$(bash "$HERE/tests/$s" 2>&1); rc=$?
  summary=$(grep -E '^[0-9]+ passed, [0-9]+ failed' <<<"$out" | tail -1)
  [[ -n "$summary" ]] || summary=$(grep -E '^SKIP' <<<"$out" | head -1)
  if ((rc == 0)); then printf '%-26s PASS  %s\n' "$s" "${summary:-ok}"; else printf '%-26s FAIL  %s\n' "$s" "${summary:-exit $rc}"; failed=$((failed + 1)); fi
done
echo
if ((failed == 0)); then echo "RESULT: PASS · ${#suites[@]} suite(s)"; else echo "RESULT: FAIL · $failed of ${#suites[@]} suite(s) failed"; exit 1; fi
