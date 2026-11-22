#!/usr/bin/env bash
# HU-14 · Static audit of how the Jenkins pipeline handles credentials (CA07).
#
# It reads the Jenkinsfile and the Shared Library (jenkins/vars) and checks that:
#   1. every secret reaches a stage only through withCredentials (the value is masked in the console log),
#   2. no credential is written literally in those files,
#   3. no secret variable is interpolated by Groovy inside a double-quoted sh step (Groovy would expand it before the
#      shell runs, so it can leak in the command line and in the process list; the shell must expand it: \$NAME),
#   4. no secret variable is printed with echo/println,
#   5. no credential is embedded in a URL (https://user:pass@host).
# It also lists every credential ID with its type, so the separation by purpose can be reviewed.
#
# It does NOT contact Jenkins: it proves how the pipeline USES credentials, not that the credentials exist or are
# stored encrypted in a running controller (that needs the live Jenkins of HU-01/HU-11).
#
# Usage: security/audit-jenkins-credentials.sh [file...]   (default: Jenkinsfile and jenkins/vars/*.groovy)
# Exit code: 0 = no violation; 1 = at least one violation (warnings do not fail); 2 = usage error.

set -Eeuo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

FILES=("$@")
if ((${#FILES[@]} == 0)); then
  FILES=(Jenkinsfile jenkins/vars/*.groovy)
fi
for f in "${FILES[@]}"; do [[ -f "$f" ]] || { echo "ERROR: no existe $f" >&2; exit 2; }; done

SENSITIVE_RE="PASSWORD|PASSWD|TOKEN|SECRET|WEBHOOK|PRIVATE_KEY|SSH_KEY|API_KEY|CG_ENV_FILE"
violations=0 warnings=0

echo "== Credenciales usadas (ID  tipo  archivo:linea)"
for f in "${FILES[@]}"; do
  awk -v file="$f" '
    { buf[NR] = $0 }
    /credentialsId[ ]*:/ {
      id = $0; sub(/.*credentialsId[ ]*:[ ]*/, "", id); sub(/[,)\]].*$/, "", id); gsub(/\047|"/, "", id)
      type = "?"
      for (i = NR; i >= NR - 2 && i > 0; i--) {
        if (match(buf[i], /(string|file|usernamePassword|sshUserPrivateKey|usernameColonPassword|certificate)\(/)) {
          type = substr(buf[i], RSTART, RLENGTH - 1); break
        }
      }
      printf "   %-34s %-18s %s:%d\n", id, type, file, NR
    }' "$f"
done | sort -u

report() { # report <VIOLATION|AVISO> <file:line> <message>
  printf '%-10s %s  %s\n' "$1" "$2" "$3"
  if [[ "$1" == VIOLACION ]]; then violations=$((violations + 1)); else warnings=$((warnings + 1)); fi
}

echo
echo "== Comprobaciones"
for f in "${FILES[@]}"; do
  n=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    # comments are not code
    trimmed=${line#"${line%%[![:space:]]*}"}
    [[ "$trimmed" == //* || "$trimmed" == \** || "$trimmed" == /\** ]] && continue

    # 2. literal credential: name = 'value' (the *Variable: arguments of withCredentials are names, not values)
    if [[ "$line" =~ (password|passwd|token|secret|apikey|api_key)[[:space:]]*[=:][[:space:]]*[\'\"]([^\'\"\$\{]{6,})[\'\"] ]] &&
       [[ ! "$line" =~ (Variable|credentialsId|description|name:) ]]; then
      report VIOLACION "$f:$n" "posible credencial escrita en el archivo"
    fi
    # 5. credential inside a URL
    if [[ "$line" =~ https?://[^/[:space:]\'\"]+:[^@/[:space:]\'\"]+@ ]]; then
      report VIOLACION "$f:$n" "credencial dentro de una URL"
    fi
    # 3. Groovy interpolation of a secret in a double-quoted sh step
    if [[ "$line" =~ sh[[:space:]]+\"  || "$line" =~ sh\(\" ]] && [[ "$line" =~ \$\{[^}]*($SENSITIVE_RE)[^}]*\} ]]; then
      report VIOLACION "$f:$n" "variable secreta interpolada por Groovy en un sh con comillas dobles (use comillas simples o \\\$NOMBRE)"
    fi
    # 4. printing a secret
    if [[ "$line" =~ (echo|println)[[:space:]\(].*($SENSITIVE_RE) ]] && [[ ! "$line" =~ (omitida|omitido|missing|skipped) ]]; then
      report AVISO "$f:$n" "se imprime una variable que podría contener un secreto"
    fi
    # environment { X = credentials('id') } exposes the secret to every stage of the pipeline
    if [[ "$line" =~ =[[:space:]]*credentials\( ]]; then
      report AVISO "$f:$n" "credentials() en environment{} expone el secreto a todas las etapas; prefiera withCredentials"
    fi
  done <"$f"
done

echo
if ((violations > 0)); then
  printf 'RESULT: FAIL · %d violación(es), %d aviso(s).\n' "$violations" "$warnings"
  exit 1
fi
printf 'RESULT: PASS · 0 violaciones, %d aviso(s). Archivos auditados: %s\n' "$warnings" "${FILES[*]}"
