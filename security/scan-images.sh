#!/usr/bin/env bash
# HU-14 · Container image vulnerability scan with Trivy and a severity gate.
#
# Usage:
#   security/scan-images.sh --own <version>      the 9 CircleGuard images built by deploy/build-images.sh (they block)
#   security/scan-images.sh --third-party        the images of security/images.catalog (reported, they do not block by default)
#   security/scan-images.sh --image <ref> [--class own|third-party]
#   security/scan-images.sh --evaluate <report.json> [--class own|third-party]   gate an existing report (no Docker, no network)
#   Options can be combined: --own 1.0.0 --third-party
#
# What it does for every image:
#   1. trivy image  -> <name>.json   (every severity, nothing filtered unless TRIVY_IGNORE_UNFIXED=true)
#   2. trivy convert -> <name>.sarif (for GitHub code scanning or any SARIF viewer)
#   3. gate: counts the vulnerabilities of the blocking severities (security/policy.env)
# Reports go to $SECURITY_REPORT_DIR (default security/reports; Jenkins archives that directory).
#
# Exit code: 0 = no blocking finding; 1 = a blocking image exceeds the threshold; 2 = a scan or a report failed
# (a scan that did not run is never reported as a pass).
#
# Requirements: bash, Docker (the Trivy scanner runs in a container, pinned in policy.env) and network access to
# download the vulnerability database. Run it from WSL, Linux or a Jenkins agent (it mounts /var/run/docker.sock
# to read locally built images). TRIVY_SKIP_DB_UPDATE=true reuses the cached database without network.

set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
# shellcheck source=security/policy.env
source "$ROOT_DIR/security/policy.env"
# shellcheck source=deploy/lib.sh
source "$ROOT_DIR/deploy/lib.sh"

: "${IMAGE_REGISTRY:=localhost:5000}"
: "${IMAGE_NAMESPACE:=circleguard}"
export IMAGE_REGISTRY IMAGE_NAMESPACE

SEVERITIES=(UNKNOWN LOW MEDIUM HIGH CRITICAL)
REPORT_DIR="$SECURITY_REPORT_DIR"
case "$REPORT_DIR" in /*) ;; *) REPORT_DIR="$ROOT_DIR/$REPORT_DIR" ;; esac
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
SUMMARY_TXT="$REPORT_DIR/summary-$STAMP.txt"
SUMMARY_TSV="$REPORT_DIR/summary-$STAMP.tsv"

FAILED=0
ERRORS=0

usage() { sed -n '2,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
log() { printf '%s\n' "$*" >&2; }
# Configuration errors exit 2, never 1 (1 means "an image is blocked").
die2() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }

sev_count() { # sev_count <report.json> <SEVERITY>
  { grep -o -E "\"Severity\": *\"$2\"" "$1" || true; } | wc -l | tr -d ' '
}

validate_policy() {
  local sev
  for sev in ${TRIVY_SEVERITY_BLOCK//,/ }; do
    local ok=0 known
    for known in "${SEVERITIES[@]}"; do [[ "$sev" == "$known" ]] && ok=1; done
    ((ok)) || die2 "TRIVY_SEVERITY_BLOCK contiene una severidad desconocida: '$sev' (use ${SEVERITIES[*]})."
  done
  [[ -n "${TRIVY_SEVERITY_BLOCK// /}" ]] || die2 "TRIVY_SEVERITY_BLOCK no puede estar vacío."
}

# evaluate <report.json> <class> <label>: prints one line, records it in the summary, returns 0 / 1 / 2.
evaluate() {
  local report=$1 class=$2 label=$3 sev blocked=0 status counts=()
  if [[ ! -s "$report" ]] || ! grep -q '"SchemaVersion"' "$report"; then
    printf '%-11s %-13s %s\n' "ERROR" "$class" "$label (el informe no es un JSON de Trivy válido: $report)" >&2
    printf 'ERROR\t%s\t%s\t-\t-\t-\t-\t-\n' "$class" "$label" >>"$SUMMARY_TSV"
    return 2
  fi
  for sev in "${SEVERITIES[@]}"; do counts+=("$(sev_count "$report" "$sev")"); done
  for sev in ${TRIVY_SEVERITY_BLOCK//,/ }; do
    local i
    for i in "${!SEVERITIES[@]}"; do
      [[ "${SEVERITIES[$i]}" == "$sev" ]] && blocked=$((blocked + counts[i]))
    done
  done
  if ((blocked == 0)); then
    status=PASS
  elif [[ "$class" == "own" || "$TRIVY_BLOCK_THIRD_PARTY" == "true" ]]; then
    status=FAIL
  else
    status=REPORT-ONLY
  fi
  # counts are in the order UNKNOWN LOW MEDIUM HIGH CRITICAL; print CRITICAL first.
  printf '%-11s %-13s C=%-4s H=%-4s M=%-4s L=%-4s U=%-4s  %s\n' "$status" "$class" \
    "${counts[4]}" "${counts[3]}" "${counts[2]}" "${counts[1]}" "${counts[0]}" "$label"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$status" "$class" "$label" \
    "${counts[4]}" "${counts[3]}" "${counts[2]}" "${counts[1]}" "${counts[0]}" >>"$SUMMARY_TSV"
  [[ "$status" == "FAIL" ]] && return 1
  return 0
}

record() { # record <rc of evaluate>
  case "$1" in 1) FAILED=$((FAILED + 1)) ;; 2) ERRORS=$((ERRORS + 1)) ;; esac
}

trivy_run() { # trivy_run <extra docker args...> -- <trivy args...>; stdout = result
  local docker_args=() trivy_args=()
  while (($#)) && [[ "$1" != "--" ]]; do docker_args+=("$1"); shift; done
  shift || true
  trivy_args=("$@")
  docker run --rm -v "$TRIVY_CACHE_VOLUME":/root/.cache "${docker_args[@]}" "$TRIVY_IMAGE" "${trivy_args[@]}"
}

scan_one() { # scan_one <image ref> <class>
  local ref=$1 class=$2 name json sarif extra=()
  name="${class}_${ref//[^A-Za-z0-9._-]/_}"
  name="${name:0:150}"
  json="$REPORT_DIR/$name.json"
  sarif="$REPORT_DIR/$name.sarif"
  [[ "$TRIVY_IGNORE_UNFIXED" == "true" ]] && extra+=(--ignore-unfixed)
  [[ "${TRIVY_SKIP_DB_UPDATE:-false}" == "true" ]] && extra+=(--skip-db-update)

  log "==> scanning $ref ($class)"
  if ! trivy_run -v /var/run/docker.sock:/var/run/docker.sock -- \
      image --quiet --no-progress --scanners vuln --format json "${extra[@]}" "$ref" >"$json" 2>"$json.err"; then
    log "    trivy failed for $ref: $(tail -n 3 "$json.err" | tr '\n' ' ')"
    rm -f "$json"
    ERRORS=$((ERRORS + 1))
    printf 'ERROR\t%s\t%s\t-\t-\t-\t-\t-\n' "$class" "$ref" >>"$SUMMARY_TSV"
    return 0
  fi
  rm -f "$json.err"
  trivy_run -v "$REPORT_DIR":/reports:ro -- \
    convert --format sarif "/reports/$name.json" >"$sarif" 2>/dev/null || log "    (no se pudo generar el SARIF de $ref)"
  local rc=0
  evaluate "$json" "$class" "$ref" || rc=$?
  record "$rc"
}

scan_own() {
  local version=$1 service
  cg_validate_semver "$version"
  for service in "${CG_SERVICES[@]}" "$CG_WEB_SERVICE"; do
    scan_one "$(cg_image_ref "$service" "$version")" own
  done
}

scan_third_party() {
  local line class ref
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    class=${line%%|*}
    ref=${line#*|}
    scan_one "$ref" "third-party"
    : "$class"
  done <"$ROOT_DIR/security/images.catalog"
}

# ---------------------------------------------------------------------------------------------- arguments
OWN_VERSION="" DO_THIRD=0 SINGLE_IMAGE="" EVAL_REPORT="" CLASS=""
while (($#)); do
  case "$1" in
    --own) OWN_VERSION=${2:?Falta la versión de --own}; shift 2 ;;
    --third-party) DO_THIRD=1; shift ;;
    --image) SINGLE_IMAGE=${2:?Falta la imagen de --image}; shift 2 ;;
    --evaluate) EVAL_REPORT=${2:?Falta el informe de --evaluate}; shift 2 ;;
    --class) CLASS=${2:?Falta la clase}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die2 "Opción desconocida: $1" ;;
  esac
done
[[ -n "$OWN_VERSION$SINGLE_IMAGE$EVAL_REPORT" || "$DO_THIRD" == 1 ]] || { usage >&2; exit 2; }
case "${CLASS:-own}" in own|third-party) ;; *) die2 "--class debe ser own o third-party." ;; esac

validate_policy
mkdir -p "$REPORT_DIR"
: >"$SUMMARY_TSV"

if [[ -n "$EVAL_REPORT" ]]; then
  rc=0
  evaluate "$EVAL_REPORT" "${CLASS:-own}" "$EVAL_REPORT" || rc=$?
  record "$rc"
else
  cg_require_docker
  log "Trivy: $TRIVY_IMAGE"
  log "Umbral que bloquea: $TRIVY_SEVERITY_BLOCK · sin arreglo ignoradas: $TRIVY_IGNORE_UNFIXED · terceros bloquean: $TRIVY_BLOCK_THIRD_PARTY"
  [[ -n "$OWN_VERSION" ]] && scan_own "$OWN_VERSION"
  [[ -n "$SINGLE_IMAGE" ]] && scan_one "$SINGLE_IMAGE" "${CLASS:-own}"
  ((DO_THIRD)) && scan_third_party
fi

{
  echo "# HU-14 image scan · $STAMP · threshold: $TRIVY_SEVERITY_BLOCK"
  column -t -s $'\t' "$SUMMARY_TSV" 2>/dev/null || cat "$SUMMARY_TSV"
} >"$SUMMARY_TXT"

if ((ERRORS > 0)); then
  log "RESULT: ERROR · $ERRORS scan(s) or report(s) could not be completed (see above). Summary: $SUMMARY_TXT"
  exit 2
elif ((FAILED > 0)); then
  log "RESULT: FAIL · $FAILED image(s) exceed the threshold ($TRIVY_SEVERITY_BLOCK). Promotion must stop. Summary: $SUMMARY_TXT"
  exit 1
fi
log "RESULT: PASS · no blocking image. Third-party findings, if any, are reported above and in $SUMMARY_TXT"
