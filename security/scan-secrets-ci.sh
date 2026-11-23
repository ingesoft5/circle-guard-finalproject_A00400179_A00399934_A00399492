#!/usr/bin/env bash
# HU-14 · Secret scan for local use and for Jenkins, with a gate.
#
# It uses the Gitleaks image and the ruleset of the project (.gitleaks.toml) like infra/scan-secrets.sh (HU-01), but it
# STREAMS the files into the container (tar over stdin) instead of bind-mounting the workspace. A bind mount does not work
# from a Jenkins agent that talks to a remote Docker daemon (DinD): the daemon cannot see the agent's workspace.
#
# What is scanned: the files that would be versioned (tracked + untracked, .gitignore respected), so local secret
# files such as .env or *.pem are out of scope by design. Values are always redacted in the report.
#
# Classification (same rules as infra/scan-secrets.sh):
#   ACTIVO    anywhere else: a secret that would be versioned -> FAILS
#   PRUEBA    fictitious value under src/test or in generated test evidence (docs/evidencias/*.html)
#   RESIDUAL  immutable Flyway migrations V2 and V3 (decision X-2 of HU-01)
#
# Usage: security/scan-secrets-ci.sh
# Exit code: 0 = no ACTIVO finding; 1 = at least one ACTIVO finding; 2 = the scan could not be completed.
# Output: $SECURITY_REPORT_DIR/secrets/worktree-<stamp>.json (redacted) and worktree-<stamp>.txt (classified summary).

set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
# shellcheck source=security/policy.env
source "$ROOT_DIR/security/policy.env"
GITLEAKS_IMAGE=${GITLEAKS_IMAGE:-zricethezav/gitleaks:v8.30.1}   # same version as infra/scan-secrets.sh

REPORT_DIR="$SECURITY_REPORT_DIR"
case "$REPORT_DIR" in /*) ;; *) REPORT_DIR="$ROOT_DIR/$REPORT_DIR" ;; esac
OUT_DIR="$REPORT_DIR/secrets"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
JSON="$OUT_DIR/worktree-$STAMP.json"
TXT="$OUT_DIR/worktree-$STAMP.txt"
mkdir -p "$OUT_DIR"

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
command -v docker >/dev/null 2>&1 || fail "Docker no está disponible."
docker info >/dev/null 2>&1 || fail "El daemon de Docker no responde."
[[ -f "$ROOT_DIR/.gitleaks.toml" ]] || fail "Falta .gitleaks.toml."
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "Se necesita un repositorio Git."

# The tar goes into the container as a stream; the report comes back on stdout, Gitleaks' own log on stderr.
# shellcheck disable=SC2016
{
  git ls-files -z --cached --others --exclude-standard | while IFS= read -r -d '' f; do
    [[ -f "$f" ]] && printf '%s\0' "$f"
  done
} | tar --null -T - -cf - 2>/dev/null |
  docker run --rm -i --entrypoint sh "$GITLEAKS_IMAGE" -c '
    mkdir -p /scan && tar -x -C /scan 2>/dev/null
    gitleaks dir /scan --config /scan/.gitleaks.toml --redact --no-banner --exit-code 0 \
      --report-format json --report-path /tmp/report.json 2>/tmp/gitleaks.log
    rc=$?; [ $rc -eq 0 ] || { cat /tmp/gitleaks.log >&2; exit $rc; }
    cat /tmp/report.json; cat /tmp/gitleaks.log >&2' >"$JSON" 2>"$OUT_DIR/gitleaks-$STAMP.log" ||
  fail "Gitleaks no pudo completar el escaneo (ver $OUT_DIR/gitleaks-$STAMP.log)."

# A report must be a JSON array; anything else is an error, never a pass.
head -c 1 "$JSON" | grep -q '\[' || fail "El informe de Gitleaks no es válido: $JSON"

# One line per finding: file, line, rule. The JSON is pretty-printed with RuleID, StartLine and File in that order.
findings=$(awk -F'"' '
  /"RuleID":/    { rule = $4 }
  /"StartLine":/ { gsub(/[^0-9]/, "", $0); line = $0 }
  /"File":/      { file = $4; sub(/^\/scan\//, "", file); print file "\t" line "\t" rule }' "$JSON")

# The counters must live in this shell (no pipe around the loop): a subshell would lose them and the gate would pass.
active=0 test_n=0 residual=0
BODY="$TXT.body"
: >"$BODY"
while IFS=$'\t' read -r file line rule; do
  [[ -n "$file" ]] || continue
  if [[ "$file" == *"/src/test/"* || ( "$file" == docs/evidencias/* && "$file" == *.html ) ]]; then
    cat=PRUEBA; test_n=$((test_n + 1))
  elif [[ "$file" =~ db/migration/V[23]__ ]]; then
    cat=RESIDUAL; residual=$((residual + 1))
  else
    cat=ACTIVO; active=$((active + 1))
  fi
  printf '%-9s %s:%s  [%s]\n' "$cat" "$file" "$line" "$rule" >>"$BODY"
done <<<"$findings"
{
  echo "# HU-14 secret scan · $STAMP · values redacted"
  echo "== total: ACTIVO=$active PRUEBA=$test_n RESIDUAL=$residual"
  sort "$BODY"
} | tee "$TXT"
rm -f "$BODY"

if ((active > 0)); then
  printf 'RESULT: FAIL · %d secreto(s) ACTIVO(S) en archivos que se versionarían. Rótelos y retírelos antes de continuar. Informe: %s\n' "$active" "$TXT" >&2
  exit 1
fi
printf 'RESULT: PASS · ningún secreto activo. Informe: %s\n' "$TXT" >&2
