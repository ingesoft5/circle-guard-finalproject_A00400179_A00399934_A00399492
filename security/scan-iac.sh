#!/usr/bin/env bash
# HU-14 · Infrastructure-as-code scan (Trivy "config") of the Terraform of HU-09, the Kubernetes manifests of HU-10 and the RBAC of
# HU-14, with a severity gate and the same expiring exceptions as the image scan.
#
#   security/scan-iac.sh                         scan the default paths and apply the gate
#   security/scan-iac.sh --path infra/terraform  scan only those paths (repeatable; relative to the repository root)
#   security/scan-iac.sh --evaluate report.json  evaluate an existing Trivy config JSON report (no Docker, no network; used by the tests)
#   security/scan-iac.sh --candidates            print the blocking findings as rows for security/exceptions.pending.tsv (owner and
#                                                justification left as PENDIENTE: a person must fill them in)
#
# Default paths: infra/terraform deploy/k8s security/k8s. Threshold: IAC_SEVERITY_BLOCK (security/policy.env, default CRITICAL,HIGH).
# Exceptions: security/exceptions.tsv, scope "iac:<file>", rules and validity in security/lib/exceptions.sh (30/90 days, review 14/30).
# Nothing is hidden: the full Trivy JSON report is kept in $SECURITY_REPORT_DIR/iac/ and every finding is counted; an exception only
# changes whether a finding blocks.
#
# The files are STREAMED into the Trivy container (tar over stdin), not bind-mounted, so it also works against a remote Docker daemon
# (Jenkins with Docker-in-Docker), like security/scan-secrets-ci.sh.
# Requirements: bash, tar, Docker (Trivy is pinned in policy.env) and network access to download the Trivy checks database.
# Exit code: 0 = nothing blocks; 1 = at least one blocking finding without a valid exception; 2 = the scan could not be completed.
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
# shellcheck source=security/policy.env
source "$ROOT_DIR/security/policy.env"
die2() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
log() { printf '%s\n' "$*" >&2; }
# shellcheck source=security/lib/exceptions.sh
source "$ROOT_DIR/security/lib/exceptions.sh"
# shellcheck source=security/lib/iac.sh
source "$ROOT_DIR/security/lib/iac.sh"

PATHS=() EVAL_REPORT="" CANDIDATES=0
while (($#)); do
  case "$1" in
    --path) PATHS+=("${2:?Falta la ruta de --path}"); shift 2 ;;
    --evaluate) EVAL_REPORT=${2:?Falta el informe de --evaluate}; shift 2 ;;
    --candidates) CANDIDATES=1; shift ;;
    -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die2 "Opción desconocida: $1" ;;
  esac
done
((${#PATHS[@]})) || PATHS=(infra/terraform deploy/k8s security/k8s)

SEVERITIES=(UNKNOWN LOW MEDIUM HIGH CRITICAL)
for sev in ${IAC_SEVERITY_BLOCK//,/ }; do
  known=0; for s in "${SEVERITIES[@]}"; do [[ "$s" == "$sev" ]] && known=1; done
  ((known)) || die2 "IAC_SEVERITY_BLOCK contiene una severidad desconocida: '$sev' (use ${SEVERITIES[*]})."
done
[[ -n "${IAC_SEVERITY_BLOCK// /}" ]] || die2 "IAC_SEVERITY_BLOCK no puede estar vacío."
exc_prepare

REPORT_DIR=${SECURITY_REPORT_DIR:-security/reports}/iac
case "$REPORT_DIR" in /*) ;; *) REPORT_DIR="$ROOT_DIR/$REPORT_DIR" ;; esac
mkdir -p "$REPORT_DIR"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)

if [[ -n "$EVAL_REPORT" ]]; then
  REPORT=$EVAL_REPORT
else
  for p in "${PATHS[@]}"; do [[ -e "$p" ]] || die2 "La ruta no existe: $p"; done
  command -v docker >/dev/null 2>&1 || die2 "Docker es necesario."
  REPORT="$REPORT_DIR/iac-$STAMP.json"
  log "Trivy: $TRIVY_IMAGE"
  log "Rutas: ${PATHS[*]} · umbral que bloquea: $IAC_SEVERITY_BLOCK"
  tar -cf - "${PATHS[@]}" | docker run --rm -i -v "${TRIVY_CACHE_VOLUME:-trivy-cache}":/root/.cache --entrypoint sh "$TRIVY_IMAGE" \
    -c 'mkdir -p /src && tar -x -C /src && trivy config --quiet --format json /src' >"$REPORT" 2>"$REPORT.err" ||
    { tail -n 3 "$REPORT.err" >&2; rm -f "$REPORT"; die2 "Trivy no pudo completar el análisis de IaC."; }
  rm -f "$REPORT.err"
fi
[[ -s "$REPORT" ]] && grep -q '"SchemaVersion"' "$REPORT" || die2 "El informe no es un JSON de Trivy válido: $REPORT"

FINDINGS=$(mktemp "${TMPDIR:-/tmp}/cg-iac.XXXXXX")
trap 'rm -f "$FINDINGS" "$EXC_VALID"' EXIT
iac_extract "$REPORT" | iac_annotate "$EXC_VALID" >"$FINDINGS"

count() { awk -F'\t' -v s="$1" '$1 == s' "$FINDINGS" | wc -l | tr -d ' '; }
blocking_line() { awk -F'\t' -v sevs=" ${IAC_SEVERITY_BLOCK//,/ } " 'index(sevs, " " $1 " ") && $6 != "EXCEPTED"' "$FINDINGS"; }
blocking_all() { awk -F'\t' -v sevs=" ${IAC_SEVERITY_BLOCK//,/ } " 'index(sevs, " " $1 " ")' "$FINDINGS"; }

if ((CANDIDATES)); then
  # rows for security/exceptions.pending.tsv: NOT active, owner and justification must be written by a person
  blocking_all | sort -u | awk -F'\t' '{ printf "%s\t%s\tiac:%s\t%s\tPENDIENTE\tPENDIENTE\t\t\t\n", $2, $3, $4, $1 }'
  exit 0
fi

C=$(count CRITICAL) H=$(count HIGH) M=$(count MEDIUM) L=$(count LOW) U=$(count UNKNOWN)
TOTAL_BLOCK=$(blocking_all | wc -l | tr -d ' ')
BLOCKING=$(blocking_line | wc -l | tr -d ' ')
EXCEPTED=$((TOTAL_BLOCK - BLOCKING))
{
  printf '# HU-14 IaC scan · %s · threshold: %s · paths: %s\n' "$STAMP" "$IAC_SEVERITY_BLOCK" "${PATHS[*]}"
  printf '# severity\trule\tresource\tfile\ttitle\texception\n'
  sort -t$'\t' -k1,1r -k2,2 "$FINDINGS"
} >"$REPORT_DIR/summary-$STAMP.tsv"

if ((BLOCKING > 0)); then
  printf '%-9s %-12s %-46s %s\n' SEVERITY RULE RESOURCE FILE
  blocking_line | awk -F'\t' '{ print (($1 == "CRITICAL") ? 0 : ($1 == "HIGH") ? 1 : 2) "\t" $0 }' | sort -t$'\t' -k1,1n -k3,3 -k4,4 -u | cut -f2- \
    | awk -F'\t' '{ r = $3; if (length(r) > 46) r = substr(r, 1, 43) "..."; printf "%-9s %-12s %-46s %s\n", $1, $2, r, $4 }' | head -40
  ((BLOCKING > 40)) && printf '... (%s más en %s)\n' "$((BLOCKING - 40))" "$REPORT_DIR/summary-$STAMP.tsv"
fi
if ((EXCEPTED > 0)); then
  blocking_all | awk -F'\t' '$6 == "EXCEPTED" { printf "    excepción vigente: %s %s (%s) en %s\n", $2, $3, $1, $4 }' | sort -u >&2
fi
if ((BLOCKING == 0)); then status=PASS; else status=FAIL; fi
printf '%-5s iac  C=%-3s H=%-3s M=%-3s L=%-3s U=%-3s  bloquean: %s · con excepción vigente: %s\n' "$status" "$C" "$H" "$M" "$L" "$U" "$BLOCKING" "$EXCEPTED"
if ((BLOCKING > 0)); then
  log "RESULT: FAIL · $BLOCKING hallazgo(s) de IaC de severidad $IAC_SEVERITY_BLOCK sin excepción vigente. La promoción debe detenerse. Resumen: $REPORT_DIR/summary-$STAMP.tsv"
  exit 1
fi
log "RESULT: PASS · ningún hallazgo de IaC supera el umbral ($IAC_SEVERITY_BLOCK). Informe: $REPORT"
