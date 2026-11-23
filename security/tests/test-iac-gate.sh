#!/usr/bin/env bash
# HU-14 · Tests of the IaC gate (security/scan-iac.sh) and its exceptions. Offline: it evaluates the synthetic Trivy config report
# security/tests/fixtures/iac-report.json (one CRITICAL Terraform finding, one HIGH Kubernetes finding, one MEDIUM, one LOW).
# "Today" is fixed with EXCEPTIONS_TODAY. Usage: security/tests/test-iac-gate.sh     Exit code: 0 = every case behaved as expected.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCAN="$HERE/../scan-iac.sh"
REPORT="$HERE/fixtures/iac-report.json"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/cg-iac-test.XXXXXX"); trap 'rm -rf "$WORK"' EXIT
TODAY=2026-11-20
PASSED=0 FAILED=0
T=$'\t'
HEAD="id${T}package${T}scope${T}severity${T}owner${T}justification${T}approved${T}last_review${T}expires"
JUST="Egress needed for node updates, tracked in the backlog"

exc() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@"; }
file() { local f="$WORK/$1.tsv"; shift; { echo "$HEAD"; (($#)) && printf '%s\n' "$@"; } >"$f"; echo "$f"; }

# check <description> <expected rc> <expected text> <exceptions file> [env assignments...] [-- extra scan args]
check() {
  local desc=$1 want_rc=$2 want_text=$3 excfile=$4 envs=() extra=() out rc
  shift 4
  while (($#)) && [[ "$1" != "--" ]]; do envs+=("$1"); shift; done
  (($#)) && shift; extra=("$@")
  out=$(env SECURITY_REPORT_DIR="$WORK/reports" EXCEPTIONS_TODAY="$TODAY" SECURITY_EXCEPTIONS_FILE="$excfile" "${envs[@]}" \
        "$SCAN" --evaluate "${extra[0]:-$REPORT}" "${extra[@]:1}" 2>&1)
  rc=$?
  if [[ "$rc" == "$want_rc" && "$out" == *"$want_text"* ]]; then printf 'PASS  %s (exit %s)\n' "$desc" "$rc"; PASSED=$((PASSED + 1))
  else printf 'FAIL  %s: expected exit %s with "%s", got exit %s\n----\n%s\n----\n' "$desc" "$want_rc" "$want_text" "$rc" "$out"; FAILED=$((FAILED + 1)); fi
}

CRIT=(SYN-0104 module.compute iac:infra/terraform/modules/compute/main.tf CRITICAL alice@example.org "$JUST")
HIGHK=(SYN-K14 "Container 'auth' of Deployment 'auth' should set 'securityContext.readOnlyRootFilesystem' to true" iac:deploy/k8s/base/apps/auth.yaml HIGH bob@example.org "$JUST")
OK_C=$(exc "${CRIT[@]}" 2026-11-10 2026-11-15 2026-12-05)
OK_H=$(exc "${HIGHK[@]}" 2026-10-25 2026-11-10 2027-01-20)

check "without exceptions the CRITICAL and the HIGH block"            1 "bloquean: 2"                     "$(file none)"
check "the counts include every severity (C=1 H=1 M=1 L=1)"            1 "C=1   H=1   M=1   L=1"           "$(file none2)"
check "the table names the blocking rule, resource and file"           1 "SYN-0104"                        "$(file none3)"
check "valid exceptions for both blocking findings -> the gate passes" 0 "con excepción vigente: 2"        "$(file valid "$OK_C" "$OK_H")"
check "the counts still list the excepted findings (nothing hidden)"   0 "C=1   H=1"                       "$(file valid2 "$OK_C" "$OK_H")"
check "EXAMPLE expired: the CRITICAL exception expired yesterday"      1 "CADUCADA"                        "$(file expired "$(exc "${CRIT[@]}" 2026-10-20 2026-11-05 2026-11-19)" "$OK_H")"
check "EXAMPLE new finding: only the HIGH is excepted, CRITICAL blocks" 1 "bloquean: 1"                    "$(file newfinding "$OK_H")"
check "a review overdue invalidates the exception"                     1 "revisión vencida"                "$(file overdue "$(exc "${CRIT[@]}" 2026-10-25 2026-11-05 2026-11-24)" "$OK_H")"
check "an exception for another resource does not cover the finding"   1 "bloquean: 1" \
  "$(file otherres "$(exc SYN-0104 module.other iac:infra/terraform/modules/compute/main.tf CRITICAL alice@example.org "$JUST" 2026-11-10 2026-11-15 2026-12-05)" "$OK_H")"
check "an exception for another file does not cover the finding"       1 "bloquean: 1" \
  "$(file otherfile "$(exc SYN-0104 module.compute iac:infra/terraform/modules/ci-server/main.tf CRITICAL alice@example.org "$JUST" 2026-11-10 2026-11-15 2026-12-05)" "$OK_H")"
check "a vulnerability-style scope (no iac: prefix) does not cover IaC" 1 "bloquean: 2" \
  "$(file noprefix "$(exc SYN-0104 module.compute infra/terraform/modules/compute/main.tf CRITICAL alice@example.org "$JUST" 2026-11-10 2026-11-15 2026-12-05)")"
check "wildcards are rejected by the shared validator (exit 2)"        2 "comodines" \
  "$(file wild "$(exc 'SYN-*' module.compute iac:infra/terraform/modules/compute/main.tf CRITICAL alice@example.org "$JUST" 2026-11-10 2026-11-15 2026-12-05)")"
check "PENDIENTE owners are rejected (exit 2)"                         2 "pendientes" \
  "$(file pend "$(exc "${CRIT[0]}" "${CRIT[1]}" "${CRIT[2]}" CRITICAL PENDIENTE "$JUST" 2026-11-10 2026-11-15 2026-12-05)")"
check "CRITICAL term over 30 days is rejected (exit 2)"                2 "plazo máximo"                    "$(file long "$(exc "${CRIT[@]}" 2026-11-10 2026-11-15 2026-12-11)")"
check "threshold CRITICAL only: the HIGH no longer blocks"             1 "bloquean: 1"                     "$(file thr)" IAC_SEVERITY_BLOCK=CRITICAL
check "threshold CRITICAL,HIGH,MEDIUM: the MEDIUM blocks too"          1 "bloquean: 3"                     "$(file thr2)" IAC_SEVERITY_BLOCK=CRITICAL,HIGH,MEDIUM
check "an unknown threshold is a configuration error (exit 2)"         2 "desconocida"                     "$(file thr3)" IAC_SEVERITY_BLOCK=SEVERE
echo 'not a trivy report' >"$WORK/invalid.json"
check "a report that is not Trivy JSON is an error, never a pass"      2 "no es un JSON de Trivy"          "$(file inv)" -- "$WORK/invalid.json"
: >"$WORK/empty.json"
check "an empty report is an error, never a pass"                      2 "no es un JSON de Trivy"          "$(file emp)" -- "$WORK/empty.json"
check "a missing report is an error, never a pass"                     2 "no es un JSON de Trivy"          "$(file mis)" -- "$WORK/does-not-exist.json"

# --candidates: rows for exceptions.pending.tsv, never active
out=$(env SECURITY_REPORT_DIR="$WORK/reports" SECURITY_EXCEPTIONS_FILE="$(file cand)" "$SCAN" --evaluate "$REPORT" --candidates 2>&1); rc=$?
rows=$(grep -c . <<<"$out")
[[ $rc == 0 && $rows == 2 && "$out" == *"SYN-0104"*"CRITICAL"*PENDIENTE*PENDIENTE* && "$out" == *"iac:deploy/k8s/base/apps/auth.yaml"* ]] &&
  { printf 'PASS  --candidates prints one PENDIENTE row per blocking finding\n'; PASSED=$((PASSED + 1)); } || { printf 'FAIL  --candidates\n%s\n' "$out"; FAILED=$((FAILED + 1)); }
printf '%s\n' "$HEAD" >"$WORK/cand-as-active.tsv"; printf '%s\n' "$out" >>"$WORK/cand-as-active.tsv"
check "candidate rows copied as-is into the active file are rejected (empty dates, PENDIENTE fields)" 2 "campos vacíos" "$WORK/cand-as-active.tsv"

# the shipped file is valid and the report is not modified
sum_before=$(cksum <"$REPORT")
out=$(env SECURITY_REPORT_DIR="$WORK/reports" "$SCAN" --evaluate "$REPORT" 2>&1); rc=$?
[[ $rc == 1 && "$sum_before" == "$(cksum <"$REPORT")" ]] && { printf 'PASS  the shipped security/exceptions.tsv grants nothing and the report is not modified\n'; PASSED=$((PASSED + 1)); } ||
  { printf 'FAIL  shipped exceptions file (exit %s)\n%s\n' "$rc" "$out"; FAILED=$((FAILED + 1)); }

printf '\n%s passed, %s failed\n' "$PASSED" "$FAILED"
((FAILED == 0))
