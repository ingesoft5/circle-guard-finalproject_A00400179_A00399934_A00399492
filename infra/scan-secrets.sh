#!/usr/bin/env bash
# HU-01 · Secret scan with Gitleaks, run locally in a container: the code never leaves the
# machine. Two scans:
#   worktree  files that would be committed now (index + untracked, ignored files excluded)
#   history   every commit, informational only (the history is never rewritten)
# Findings are classified, never hidden: ACTIVO (real secret in a file to be committed),
# PRUEBA (fictitious value under src/test), RESIDUAL (immutable Flyway migrations V2/V3,
# decision X-2) and, for history, HISTORICO. Values are always redacted.
# Exit code 1 when the worktree has ACTIVO findings.

# shellcheck source=bootstrap/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap/lib/common.sh"

GITLEAKS_IMAGE=zricethezav/gitleaks:v8.30.1

usage() {
  cat <<'EOF'
Uso: infra/scan-secrets.sh [--worktree] [--history]
  Sin opciones ejecuta ambos. Reportes (valores redactados) en infra/security/reports/.
EOF
}

gitleaks() { # gitleaks <mount source> <mode> <report name>
  docker run --rm -v "$1:/scan:ro" -v "$REPO_DIR/.gitleaks.toml:/config/gitleaks.toml:ro" -v "$REPORTS:/reports" \
    -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' \
    "$GITLEAKS_IMAGE" "$2" /scan --config /config/gitleaks.toml --redact --no-banner --exit-code 0 \
    --report-format json --report-path "/reports/$3" >&2
}

summarize() { # summarize <report json> <worktree|history>
  python3 - "$1" "$2" <<'PY'
import json, re, sys
findings = json.load(open(sys.argv[1]))
kind = sys.argv[2]
def path_of(f):
    return re.sub(r"^/scan/", "", f["File"].replace("\\", "/"))
def category(f):
    path = path_of(f)
    if "/src/test/" in path:
        return "PRUEBA"
    if re.search(r"db/migration/V[23]__", path):
        return "RESIDUAL"
    return "ACTIVO" if kind == "worktree" else "HISTORICO"
rows = sorted((category(f), path_of(f), f["StartLine"], f["RuleID"], (f.get("Commit") or "")[:7]) for f in findings)
counts = {}
for r in rows:
    counts[r[0]] = counts.get(r[0], 0) + 1
print(f"== {kind}: {len(rows)} hallazgos " + " ".join(f"{k}={v}" for k, v in sorted(counts.items())))
for cat, path, line, rule, commit in rows:
    print(f"  {cat:9} {path}:{line}  [{rule}]" + (f"  commit {commit}" if commit else ""))
PY
}

cg_parse_flags "$@"
CG_MODE=solo-lectura CG_TARGET=local
cg_start_log scan-secrets
require_cmd docker git python3 tar
MODES=("${CG_ARGS[@]}")
((${#MODES[@]})) || MODES=(--worktree --history)
REPORTS="$INFRA_DIR/security/reports"
mkdir -p "$REPORTS"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
ACTIVE=0

for mode in "${MODES[@]}"; do
  case "$mode" in
    --worktree)
      SNAPSHOT=$(mktemp -d)
      trap 'rm -rf "$SNAPSHOT"' EXIT
      (cd "$REPO_DIR" && git ls-files -z --cached --others --exclude-standard |
        xargs -0 -I{} sh -c 'test -f "$1" && printf "%s\0" "$1"' _ {} | tar --null -T - -cf -) | tar -xf - -C "$SNAPSHOT"
      info "árbol de trabajo: $(find "$SNAPSHOT" -type f | wc -l) archivos que se versionarían (ignorados excluidos)"
      gitleaks "$SNAPSHOT" dir "$STAMP-worktree.json"
      summarize "$REPORTS/$STAMP-worktree.json" worktree | tee "$REPORTS/$STAMP-worktree-summary.txt" >&2
      ACTIVE=$(grep -c '^  ACTIVO' "$REPORTS/$STAMP-worktree-summary.txt" || true)
      ;;
    --history)
      info "historial: $(git -C "$REPO_DIR" rev-list --all --count) commits (solo lectura; no se reescribe)"
      gitleaks "$REPO_DIR" git "$STAMP-history.json"
      summarize "$REPORTS/$STAMP-history.json" history | tee "$REPORTS/$STAMP-history-summary.txt" >&2
      ;;
    *) die "opción desconocida: $mode" ;;
  esac
done
info "reportes (valores redactados): infra/security/reports/$STAMP-*"
if ((ACTIVE > 0)); then
  log FAIL "el árbol de trabajo contiene $ACTIVE secretos ACTIVOS"
  exit 1
fi
log PASS "el árbol de trabajo no contiene secretos activos"
