#!/usr/bin/env bash
# HU-15 · Runs the offline tests of the performance evaluator (tests/performance/tests/test_evaluate.py). Needs python3 (standard library only).
# Exit code: 0 = every test passed or python3 is not installed (SKIP); 1 = a test failed.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
command -v python3 >/dev/null 2>&1 || { echo "SKIP python3 is not installed: the performance evaluator tests were not run"; exit 0; }
out=$(python3 -W ignore -I "$HERE/../../tests/performance/tests/test_evaluate.py" 2>&1); rc=$?
echo "$out" | tail -4
n=$(grep -o -E '^Ran [0-9]+' <<<"$out" | grep -o '[0-9]*')
if ((rc == 0)); then echo "${n:-0} passed, 0 failed"; else echo "FAILED"; echo "$out"; fi
exit "$rc"
