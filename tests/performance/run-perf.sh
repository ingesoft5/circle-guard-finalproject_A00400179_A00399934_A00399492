#!/usr/bin/env bash
# HU-15 · Runs the Locust scenarios in steps against a controlled environment (never production), draws the charts and compares the
# result with the declared objectives (targets.json).
#
#   export PERF_TARGET_ENV=local PERF_USERNAME=<test user>
#   read -rs -p "Test user password: " PERF_PASSWORD; export PERF_PASSWORD                  # no echo, never written to disk
#   tests/performance/run-perf.sh --network circleguard-hu14val_circleguard --host http://web:8080 --seed
#   tests/performance/run-perf.sh --host https://dev.example.org --scenario survey --steps "10 50" --duration 2m
#
# Options (defaults in brackets):
#   --host URL         base URL of the web client proxy under test            [http://web:8080]
#   --network NAME     Docker network to join (when the target is a Compose stack) [none: the host network is used as is]
#   --scenario NAME    access | survey | both                                 [both]
#   --steps "A B C"    concurrent users of each step                          [10 50 100]
#   --duration D       length of each step (Locust syntax: 30s, 5m)           [5m]
#   --spawn-rate N     users started per second                               [10]
#   --out DIR          results directory                                      [tests/performance/results/<timestamp>]
#   --seed             first make sure an active questionnaire exists (synthetic, idempotent; see seed_questionnaire.py)
#   --warmup D         warm-up run before each scenario, not measured: 2 users for D (Locust syntax); 0 = none  [20s]
#   --enforce          exit 1 when an objective is not met (default: report only)
# Per-user request rate: PERF_ACCESS_RPS_PER_USER (default 2) and PERF_SURVEY_RPS_PER_USER (default 0.5).
# Needs Docker. Locust runs in a pinned image; the scripts evaluate.py and charts.py run in the same image (Python standard library only).
# Exit code: 0 = done (and objectives met if --enforce), 1 = --enforce and an objective not met, 2 = configuration or execution error.
set -Eeuo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
: "${LOCUST_IMAGE:=locustio/locust:2.32.5@sha256:13351310332ac2d459e01a2b340432c5bfd509fa09838d2aa9d1f15dc49ff135}"

HOST=http://web:8080 NETWORK="" SCENARIO=both STEPS="10 50 100" DURATION=5m SPAWN=10 OUT="" ENFORCE=0 SEED=0 WARMUP=20s
die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
while (($#)); do
  case "$1" in
    --host) HOST=${2:?}; shift 2 ;;
    --network) NETWORK=${2:?}; shift 2 ;;
    --scenario) SCENARIO=${2:?}; shift 2 ;;
    --steps) STEPS=${2:?}; shift 2 ;;
    --duration) DURATION=${2:?}; shift 2 ;;
    --spawn-rate) SPAWN=${2:?}; shift 2 ;;
    --out) OUT=${2:?}; shift 2 ;;
    --seed) SEED=1; shift ;;
    --warmup) WARMUP=${2:?}; shift 2 ;;
    --enforce) ENFORCE=1; shift ;;
    -h|--help) sed -n "2,25p" "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

case "${PERF_TARGET_ENV:-}" in local|dev|stage) ;; *) die "PERF_TARGET_ENV must be local, dev or stage: these tests never run against production." ;; esac
case "$SCENARIO" in access|survey|both) ;; *) die "--scenario must be access, survey or both." ;; esac
[[ "$SCENARIO" == survey ]] || { [[ -n "${PERF_USERNAME:-}" && -n "${PERF_PASSWORD:-}" ]] || die "PERF_USERNAME and PERF_PASSWORD are required for the access scenario."; }
for s in $STEPS; do [[ "$s" =~ ^[0-9]+$ && "$s" -gt 0 ]] || die "--steps only accepts positive integers (got '$s')."; done
command -v docker >/dev/null || die "Docker is required."

[[ -n "$OUT" ]] || OUT="$HERE/results/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$OUT"
NET_ARGS=(); [[ -z "$NETWORK" ]] || NET_ARGS=(--network "$NETWORK")
scenarios=(access survey); [[ "$SCENARIO" == both ]] || scenarios=("$SCENARIO")

echo "Locust: $LOCUST_IMAGE"
echo "Environment: $PERF_TARGET_ENV · host: $HOST · scenarios: ${scenarios[*]} · steps: $STEPS users · $DURATION each · spawn rate $SPAWN/s · warm-up: $WARMUP"
echo "Results: $OUT"

run_step() { # run_step <scenario> <class> <users> [duration] [subdirectory of the results: not evaluated]
  local scenario=$1 class=$2 users=$3 duration=${4:-$DURATION} sub=${5:-} rc=0 prefix
  prefix="${sub:+$sub/}$scenario-u$users"
  mkdir -p "$OUT/${sub:-.}"
  echo "==> $scenario with $users users, $duration${sub:+ ($sub, not measured)}"
  docker run --rm "${NET_ARGS[@]}" -v "$HERE":/perf:ro -v "$OUT":/out \
    -e PERF_SCENARIO="$scenario" -e PERF_TARGET_ENV -e PERF_USERNAME -e PERF_PASSWORD \
    -e PERF_ACCESS_RPS_PER_USER -e PERF_SURVEY_RPS_PER_USER \
    "$LOCUST_IMAGE" -f /perf/locustfile.py "$class" --headless --host "$HOST" --users "$users" --spawn-rate "$SPAWN" \
    --run-time "$duration" --csv "/out/$prefix" --csv-full-history --html "/out/$prefix.html" \
    --only-summary >"$OUT/$prefix.log" 2>&1 || rc=$?
  # Locust exits 1 when some request failed: that is a result (evaluated below), not an execution error.
  if ((rc > 1)); then tail -n 15 "$OUT/$prefix.log" >&2; die "Locust failed to run ($scenario, $users users, exit $rc)."; fi
}

if ((SEED)); then
  echo "==> seeding the questionnaire"
  docker run --rm "${NET_ARGS[@]}" -v "$HERE":/perf:ro -e PERF_TARGET_ENV --entrypoint python3 "$LOCUST_IMAGE" /perf/seed_questionnaire.py "$HOST"
fi

for scenario in "${scenarios[@]}"; do
  class=AccessValidationUser; [[ "$scenario" == survey ]] && class=SurveySubmissionUser
  # Warm-up: a cold JVM answers the first requests far slower. This run is kept in warmup/ and never evaluated.
  [[ "$WARMUP" == 0 ]] || run_step "$scenario" "$class" 2 "$WARMUP" warmup
  for users in $STEPS; do run_step "$scenario" "$class" "$users"; done
done

py() { docker run --rm -v "$HERE":/perf:ro -v "$OUT":/out --entrypoint python3 "$LOCUST_IMAGE" "$@"; }
py /perf/charts.py --results /out --out /out/charts
rc=0
py /perf/evaluate.py --targets /perf/targets.json --results /out --out-json /out/evaluation.json --out-md /out/evaluation.md \
  $( ((ENFORCE)) && echo --enforce ) || rc=$?
exit "$rc"
