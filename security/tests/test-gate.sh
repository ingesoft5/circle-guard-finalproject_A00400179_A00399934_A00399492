#!/usr/bin/env bash
# HU-14 · Tests of the severity gate of security/scan-images.sh. Offline: it needs neither Docker nor network, it
# evaluates the synthetic reports of security/tests/fixtures/ (see the README there).
# Usage: security/tests/test-gate.sh        Exit code: 0 = every case behaved as expected.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCAN="$HERE/../scan-images.sh"
FIX="$HERE/fixtures"
PASSED=0 FAILED=0

# case <description> <expected exit code> <expected text in the output> <env assignments...> -- <scan args...>
check() {
  local desc=$1 want_rc=$2 want_text=$3 envs=() out rc
  shift 3
  while (($#)) && [[ "$1" != "--" ]]; do envs+=("$1"); shift; done
  shift
  out=$(env SECURITY_REPORT_DIR="${TMPDIR:-/tmp}/cg-gate-test" "${envs[@]}" "$SCAN" "$@" 2>&1)
  rc=$?
  if [[ "$rc" == "$want_rc" && "$out" == *"$want_text"* ]]; then
    printf 'PASS  %s (exit %s)\n' "$desc" "$rc"; PASSED=$((PASSED + 1))
  else
    printf 'FAIL  %s: expected exit %s with "%s", got exit %s\n----\n%s\n----\n' "$desc" "$want_rc" "$want_text" "$rc" "$out"
    FAILED=$((FAILED + 1))
  fi
}

check "own image without vulnerabilities passes"                       0 "PASS"        -- --evaluate "$FIX/clean.json" --class own
check "own image with only MEDIUM/LOW passes at the default threshold" 0 "PASS"        -- --evaluate "$FIX/medium-only.json" --class own
check "own image with a HIGH vulnerability is blocked"                 1 "FAIL"        -- --evaluate "$FIX/high.json" --class own
check "own image with a CRITICAL vulnerability is blocked"             1 "FAIL"        -- --evaluate "$FIX/critical.json" --class own
check "counts every severity of a mixed report"                        1 "C=1    H=2    M=1    L=1    U=1" -- --evaluate "$FIX/mixed.json" --class own
check "threshold CRITICAL only: a HIGH no longer blocks"               0 "PASS"        TRIVY_SEVERITY_BLOCK=CRITICAL -- --evaluate "$FIX/high.json" --class own
check "threshold CRITICAL only: a CRITICAL still blocks"               1 "FAIL"        TRIVY_SEVERITY_BLOCK=CRITICAL -- --evaluate "$FIX/critical.json" --class own
check "threshold MEDIUM: a MEDIUM blocks"                              1 "FAIL"        TRIVY_SEVERITY_BLOCK=CRITICAL,HIGH,MEDIUM -- --evaluate "$FIX/medium-only.json" --class own
check "third-party image with HIGH is reported but does not block"     0 "REPORT-ONLY" -- --evaluate "$FIX/high.json" --class third-party
check "third-party image blocks when the policy says so"               1 "FAIL"        TRIVY_BLOCK_THIRD_PARTY=true -- --evaluate "$FIX/high.json" --class third-party
check "a report that is not Trivy JSON is an error, never a pass"      2 "ERROR"       -- --evaluate "$FIX/invalid.json" --class own
check "an empty report is an error, never a pass"                      2 "ERROR"       -- --evaluate "$FIX/empty.json" --class own
check "a missing report is an error, never a pass"                     2 "ERROR"       -- --evaluate "$FIX/does-not-exist.json" --class own
check "an unknown severity in the policy is rejected (config error)"      2 "desconocida" TRIVY_SEVERITY_BLOCK=SEVERE -- --evaluate "$FIX/high.json" --class own

# A scan that could not run must exit 2 (the pipeline fails the build), never 1 (which means "findings" and only marks UNSTABLE in report
# mode). Found in Jenkins build #10: the agent had no 'docker compose' plugin and the dependency scan was reported as "findings".
FAKEBIN=$(mktemp -d); trap 'rm -rf "$FAKEBIN"' EXIT
printf '#!/usr/bin/env bash\n[[ "${1:-}" == compose ]] && exit 1\nexit 0\n' >"$FAKEBIN/docker"; chmod +x "$FAKEBIN/docker"
check "Docker without the compose plugin is an error (2), not a finding (1)" 2 "docker compose" PATH="$FAKEBIN:$PATH" -- --own 1.0.0
DEPS="$HERE/../scan-dependencies.sh"
out=$(env SECURITY_REPORT_DIR="${TMPDIR:-/tmp}/cg-gate-test-deps" CG_GRADLE=/bin/false "$DEPS" 2>&1); rc=$?
if [[ "$rc" == 2 && "$out" == *"no se ejecutó"* ]]; then printf 'PASS  a failing Gradle is an error (2), not a finding (1) (exit %s)\n' "$rc"; PASSED=$((PASSED + 1))
else printf 'FAIL  failing Gradle: expected exit 2, got %s\n%s\n' "$rc" "$out"; FAILED=$((FAILED + 1)); fi
out=$(env SECURITY_REPORT_DIR="${TMPDIR:-/tmp}/cg-gate-test-deps" CG_SKIP_GRADLE=true "$DEPS" circleguard-nonexistent-service 2>&1); rc=$?
if [[ "$rc" == 2 && "$out" == *"no se ejecutó"* ]]; then printf 'PASS  a missing SBOM is an error (2), not a finding (1) (exit %s)\n' "$rc"; PASSED=$((PASSED + 1))
else printf 'FAIL  missing SBOM: expected exit 2, got %s\n%s\n' "$rc" "$out"; FAILED=$((FAILED + 1)); fi

printf '\n%s passed, %s failed\n' "$PASSED" "$FAILED"
((FAILED == 0))
