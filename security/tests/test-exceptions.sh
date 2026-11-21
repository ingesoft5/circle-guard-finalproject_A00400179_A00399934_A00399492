#!/usr/bin/env bash
# HU-14 · Tests of the vulnerability exceptions with expiry (security/lib/exceptions.sh, used by scan-images.sh).
# Offline: synthetic report + exception files written here. "Today" is fixed with EXCEPTIONS_TODAY so the dates never drift.
# Usage: security/tests/test-exceptions.sh        Exit code: 0 = every case behaved as expected.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCAN="$HERE/../scan-images.sh"
REPORT="$HERE/fixtures/exceptions-report.json"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/cg-exc-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
TODAY=2026-11-20
PASSED=0 FAILED=0
T=$'\t'
HEAD="id${T}package${T}scope${T}severity${T}owner${T}justification${T}approved${T}last_review${T}expires"
JUST="Fix needs a major framework upgrade, tracked in the backlog"

# exc <id> <package> <scope> <severity> <owner> <justification> <approved> <last_review> <expires>
exc() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@"; }
# file <name> <rows...>: writes an exceptions file with the header and prints its path
file() { local f="$WORK/$1.tsv"; shift; { echo "$HEAD"; (($#)) && printf '%s\n' "$@"; } >"$f"; echo "$f"; }

# check <description> <expected rc> <expected text> <exceptions file> [env assignments...]: evaluates the synthetic report as image "test-image"
check() {
  local desc=$1 want_rc=$2 want_text=$3 excfile=$4 out rc
  shift 4
  out=$(env SECURITY_REPORT_DIR="$WORK/reports" EXCEPTIONS_TODAY="$TODAY" SECURITY_EXCEPTIONS_FILE="$excfile" "$@" \
        "$SCAN" --evaluate "$REPORT" --class own --scope test-image 2>&1)
  rc=$?
  if [[ "$rc" == "$want_rc" && "$out" == *"$want_text"* ]]; then
    printf 'PASS  %s (exit %s)\n' "$desc" "$rc"; PASSED=$((PASSED + 1))
  else
    printf 'FAIL  %s: expected exit %s with "%s", got exit %s\n----\n%s\n----\n' "$desc" "$want_rc" "$want_text" "$rc" "$out"
    FAILED=$((FAILED + 1))
  fi
}

A_CRIT=(SYNTHETIC-0101 example.org:lib-a test-image CRITICAL "alice@example.org" "$JUST")
B_HIGH=(SYNTHETIC-0102 example.org:lib-b test-image HIGH "bob@example.org" "$JUST")
OK_A=$(exc "${A_CRIT[@]}" 2026-11-10 2026-11-15 2026-12-05)
OK_B=$(exc "${B_HIGH[@]}" 2026-10-25 2026-11-10 2027-01-20)

# ---- the three examples of the delivery: valid, expired, new vulnerability
check "EXAMPLE valid: both findings covered by valid exceptions -> the gate passes" 0 "excepciones vigentes: 2" "$(file valid "$OK_A" "$OK_B")"
check "the counts still show every vulnerability (nothing is hidden)" 0 "C=1    H=1" "$(file valid2 "$OK_A" "$OK_B")"
check "EXAMPLE expired: the CRITICAL exception expired yesterday -> blocks again" 1 "CADUCADA" \
  "$(file expired "$(exc "${A_CRIT[@]}" 2026-10-20 2026-11-05 2026-11-19)" "$OK_B")"
check "EXAMPLE new vulnerability: only the HIGH is excepted, the CRITICAL (new) still blocks" 1 "FAIL" "$(file newvuln "$OK_B")"

# ---- validity edges
check "a valid exception that expires today still applies (last valid day)" 0 "PASS" \
  "$(file today "$(exc "${A_CRIT[@]}" 2026-10-21 2026-11-10 2026-11-20)" "$OK_B")"
check "CRITICAL with the 14-day review overdue is invalidated" 1 "revisión vencida" \
  "$(file overdue "$(exc "${A_CRIT[@]}" 2026-10-25 2026-11-05 2026-11-24)" "$OK_B")"
check "HIGH with the 30-day review overdue is invalidated" 1 "revisión vencida" \
  "$(file overdueh "$OK_A" "$(exc "${B_HIGH[@]}" 2026-09-20 2026-10-10 2026-12-15)")"
check "an exception of another package does not cover the finding" 1 "FAIL" \
  "$(file otherpkg "$(exc SYNTHETIC-0101 example.org:other test-image CRITICAL alice@example.org "$JUST" 2026-11-10 2026-11-15 2026-12-05)" "$OK_B")"
check "an exception of another image does not cover the finding" 1 "FAIL" \
  "$(file otherscope "$(exc SYNTHETIC-0101 example.org:lib-a another-image CRITICAL alice@example.org "$JUST" 2026-11-10 2026-11-15 2026-12-05)" "$OK_B")"
check "an exception for HIGH does not cover the same finding now reported as CRITICAL" 1 "FAIL" \
  "$(file sevmismatch "$(exc SYNTHETIC-0101 example.org:lib-a test-image HIGH alice@example.org "$JUST" 2026-11-10 2026-11-15 2026-12-05)" "$OK_B")"
check "an empty exceptions file: the gate blocks" 1 "FAIL" "$(file none)"

# ---- unauthorized or malformed exceptions are configuration errors (exit 2), never a silent pass
bad() { exc SYNTHETIC-0101 example.org:lib-a test-image CRITICAL alice@example.org "$JUST" 2026-11-10 2026-11-15 2026-12-05; }
check "wildcard in the id is rejected" 2 "comodines" \
  "$(file wild "$(exc 'SYNTHETIC-*' example.org:lib-a test-image CRITICAL alice@example.org "$JUST" 2026-11-10 2026-11-15 2026-12-05)")"
check "global scope 'all' is rejected" 2 "comodines" \
  "$(file global "$(exc SYNTHETIC-0101 example.org:lib-a all CRITICAL alice@example.org "$JUST" 2026-11-10 2026-11-15 2026-12-05)")"
check "missing owner is rejected" 2 "campos vacíos" \
  "$(file noowner "$(exc SYNTHETIC-0101 example.org:lib-a test-image CRITICAL ' ' "$JUST" 2026-11-10 2026-11-15 2026-12-05)")"
check "missing expiry (permanent exception) is rejected" 2 "campos vacíos" \
  "$(file noexpiry "$(exc SYNTHETIC-0101 example.org:lib-a test-image CRITICAL alice@example.org "$JUST" 2026-11-10 2026-11-15 ' ')")"
check "PENDIENTE owner is rejected" 2 "pendientes" \
  "$(file pending "$(exc SYNTHETIC-0101 example.org:lib-a test-image CRITICAL PENDIENTE "$JUST" 2026-11-10 2026-11-15 2026-12-05)")"
check "too short a justification is rejected" 2 "justificación" \
  "$(file shortjust "$(exc SYNTHETIC-0101 example.org:lib-a test-image CRITICAL alice@example.org later 2026-11-10 2026-11-15 2026-12-05)")"
check "CRITICAL term of 31 days is rejected" 2 "plazo máximo" "$(file crit31 "$(exc "${A_CRIT[@]}" 2026-11-10 2026-11-15 2026-12-11)")"
check "CRITICAL term of exactly 30 days is accepted" 0 "PASS" "$(file crit30 "$(exc "${A_CRIT[@]}" 2026-11-10 2026-11-15 2026-12-10)" "$OK_B")"
check "HIGH term of 91 days is rejected" 2 "plazo máximo" "$(file high91 "$(exc "${B_HIGH[@]}" 2026-10-25 2026-11-10 2027-01-24)")"
check "an approval date in the future is rejected" 2 "futuro" "$(file future "$(exc "${A_CRIT[@]}" 2026-11-25 2026-11-25 2026-12-10)")"
check "an invalid date is rejected" 2 "fecha válida" "$(file baddate "$(exc "${A_CRIT[@]}" 2026-13-40 2026-11-15 2026-12-05)")"
check "a severity that is not CRITICAL/HIGH is rejected" 2 "CRITICAL o HIGH" \
  "$(file badsev "$(exc SYNTHETIC-0101 example.org:lib-a test-image MEDIUM alice@example.org "$JUST" 2026-11-10 2026-11-15 2026-12-05)")"
check "a row with the wrong number of columns is rejected" 2 "9 columnas" "$(file cols "SYNTHETIC-0101${T}example.org:lib-a${T}test-image")"

# ---- the policy stays as it was
check "thresholds are unchanged: CRITICAL and HIGH both block by default" 1 "FAIL" "$(file thr)"
check "an expired exception never lowers the threshold: CRITICAL-only still blocks" 1 "FAIL" \
  "$(file thr2 "$(exc "${A_CRIT[@]}" 2026-10-20 2026-11-05 2026-11-19)")" TRIVY_SEVERITY_BLOCK=CRITICAL
if grep -q ':=CRITICAL,HIGH}' "$HERE/../policy.env"; then printf 'PASS  the default threshold in policy.env is still CRITICAL,HIGH\n'; PASSED=$((PASSED + 1))
else printf 'FAIL  the default threshold in policy.env changed\n'; FAILED=$((FAILED + 1)); fi
if [[ "$(grep -c SYNTHETIC "$REPORT")" == 2 ]]; then printf 'PASS  the evaluated report is not modified by exceptions (both vulnerabilities still listed)\n'; PASSED=$((PASSED + 1))
else printf 'FAIL  the report changed\n'; FAILED=$((FAILED + 1)); fi
# the shipped file: valid and granting nothing; the pending candidates are never read by the gate
out=$(env SECURITY_REPORT_DIR="$WORK/reports" "$SCAN" --evaluate "$REPORT" --class own --scope test-image 2>&1); rc=$?
if [[ "$rc" == 1 ]]; then printf 'PASS  the shipped security/exceptions.tsv is valid and grants nothing\n'; PASSED=$((PASSED + 1))
else printf 'FAIL  the shipped exceptions file misbehaves (exit %s):\n%s\n' "$rc" "$out"; FAILED=$((FAILED + 1)); fi

printf '\n%s passed, %s failed\n' "$PASSED" "$FAILED"
((FAILED == 0))
