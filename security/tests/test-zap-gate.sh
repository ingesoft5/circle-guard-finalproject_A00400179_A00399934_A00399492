#!/usr/bin/env bash
# HU-15 · Tests of the OWASP ZAP gate (security/zap/evaluate-zap.sh). Offline: it evaluates the synthetic reports of
# security/tests/fixtures/zap-*.json (not real scan results). Usage: security/tests/test-zap-gate.sh   Exit code: 0 = every case passed.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GATE="$HERE/../zap/evaluate-zap.sh"
FIX="$HERE/fixtures"
PASSED=0 FAILED=0

# check <description> <expected exit code> <expected text> <env assignments...> -- <report>
check() {
  local desc=$1 want_rc=$2 want_text=$3 envs=() out rc
  shift 3
  while (($#)) && [[ "$1" != "--" ]]; do envs+=("$1"); shift; done
  shift
  out=$(env "${envs[@]}" "$GATE" "$@" 2>&1)
  rc=$?
  if [[ "$rc" == "$want_rc" && "$out" == *"$want_text"* ]]; then
    printf 'PASS  %s (exit %s)\n' "$desc" "$rc"; PASSED=$((PASSED + 1))
  else
    printf 'FAIL  %s: expected exit %s with "%s", got exit %s\n----\n%s\n----\n' "$desc" "$want_rc" "$want_text" "$rc" "$out"
    FAILED=$((FAILED + 1))
  fi
}

check "a report with only Low and Informational alerts passes"           0 "PASS"          -- "$FIX/zap-clean.json"
check "a High alert blocks at the default threshold"                     1 "FAIL"          -- "$FIX/zap-high.json"
check "the blocking alert is marked in the table"                        1 "<- bloquea"    -- "$FIX/zap-high.json"
check "a Medium alert does not block at the default threshold (High)"    0 "PASS"          -- "$FIX/zap-medium.json"
check "threshold Medium: a Medium alert blocks"                          1 "FAIL"          ZAP_BLOCK_RISK=Medium -- "$FIX/zap-medium.json"
check "threshold Low: a Low alert blocks"                                1 "FAIL"          ZAP_BLOCK_RISK=Low -- "$FIX/zap-clean.json"
check "counts the distinct alerts by risk"                               1 "High=1 Medium=1 Low=1 Informational=0" -- "$FIX/zap-high.json"
check "lists the instance count of an alert"                             1 "Synthetic high finding" -- "$FIX/zap-high.json"
check "an unknown threshold is a configuration error"                    2 "debe ser High"  ZAP_BLOCK_RISK=Critical -- "$FIX/zap-high.json"
check "a report that is not a ZAP report is an error, never a pass"      2 "no es un JSON de ZAP" -- "$FIX/zap-invalid.json"
check "a report without scanned sites is an error, never a pass"         2 "ningún sitio"  -- "$FIX/zap-nosites.json"
check "a missing report is an error, never a pass"                       2 "no existe"     -- "$FIX/does-not-exist.json"
check "no argument is an error"                                          2 "Uso"           --

printf '\n%s passed, %s failed\n' "$PASSED" "$FAILED"
((FAILED == 0))
