#!/usr/bin/env bash
# HU-14 · Vulnerability exceptions with an expiry date. Sourced by security/scan-images.sh (not meant to be run on its own).
#
# An exception lets ONE identified finding (vulnerability id + package + scope + severity) stop blocking the gate for a limited time.
# It never hides anything: the Trivy JSON/SARIF reports and the summary counts keep listing every vulnerability.
#
# File format (TSV, versioned in the repository, see security/exceptions.tsv):
#   id  package  scope  severity  owner  justification  approved  last_review  expires      (dates: YYYY-MM-DD, UTC)
#
# Rules (thresholds live in security/policy.env):
#   - every field is mandatory; id, package and scope are exact values: no wildcards, no "all", no pattern;
#   - severity is CRITICAL or HIGH; the term (expires - approved) is at most 30 days for CRITICAL and 90 for HIGH;
#   - a review is due every 14 days (CRITICAL) / 30 days (HIGH): the exception is valid while today <= last_review + interval.
#     Reviewing means a pull request that moves last_review forward (and still respects expires);
#   - past expires, or with the review overdue, the exception is NOT valid any more and the gate blocks again (a warning says why);
#   - an entry that breaks the rules above is a configuration error (exit 2), never silently ignored;
#   - a finding matches only if id, package, scope and severity are all equal: a new vulnerability, another package or a
#     higher severity does not match.
# Configuration errors call die2 (defined by the caller).

# EXC_VALID: temp file with the currently valid exceptions (same columns). Set by exc_prepare.
EXC_VALID=""

exc_epoch() { date -u -d "$1 00:00:00" +%s 2>/dev/null; }

exc_check_date() { # exc_check_date <line number> <field name> <value>
  [[ "$3" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && exc_epoch "$3" >/dev/null ||
    die2 "excepciones línea $1: '$2' debe ser una fecha válida AAAA-MM-DD (recibido '$3')."
}

# exc_prepare: validates the exceptions file and writes the valid ones to $EXC_VALID.
exc_prepare() {
  local file=${SECURITY_EXCEPTIONS_FILE:-$ROOT_DIR/security/exceptions.tsv}
  EXC_VALID=$(mktemp "${TMPDIR:-/tmp}/cg-exc.XXXXXX")
  trap 'rm -f "$EXC_VALID"' EXIT
  if [[ ! -e "$file" ]]; then
    [[ -z "${SECURITY_EXCEPTIONS_FILE:-}" ]] || die2 "SECURITY_EXCEPTIONS_FILE no existe: $file"
    return 0
  fi
  local today today_s n=0 id pkg scope sev owner just approved review expires
  today=${EXCEPTIONS_TODAY:-$(date -u +%F)}
  exc_check_date "-" "EXCEPTIONS_TODAY" "$today"
  today_s=$(exc_epoch "$today")
  local max_days review_days a_s r_s e_s limit
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    line=${line%$'\r'}
    [[ -z "${line// /}" || "$line" == \#* || "$line" == id$'\t'* ]] && continue
    # Fields are split on a non-whitespace delimiter so that an empty field is not collapsed away.
    local fields
    fields=$(printf '%s' "$line" | tr '\t' '\037')
    [[ "$(tr -cd '\037' <<<"$fields" | wc -c | tr -d ' ')" == 8 ]] ||
      die2 "excepciones línea $n: se esperan 9 columnas separadas por tabulador (id package scope severity owner justification approved last_review expires)."
    IFS=$'\037' read -r id pkg scope sev owner just approved review expires <<<"$fields"
    local f
    for f in "$id" "$pkg" "$scope" "$sev" "$owner" "$just" "$approved" "$review" "$expires"; do
      [[ -n "${f// /}" ]] || die2 "excepciones línea $n: hay campos vacíos; todos son obligatorios (responsable, justificación y caducidad incluidos)."
    done
    for f in "$id" "$pkg" "$scope"; do
      case "${f,,}" in
        *'*'*|*'?'*|*'['*|*']'*|*'|'*|all|any)
          die2 "excepciones línea $n: no se admiten comodines ni exclusiones globales ('$f'): id, package y scope son valores exactos." ;;
      esac
    done
    shopt -s nocasematch
    [[ ! "$owner" =~ ^(pendiente|tbd|todo|n/a|-)$ && ! "$just" =~ ^(pendiente|tbd|todo|n/a|-)$ ]] ||
      { shopt -u nocasematch; die2 "excepciones línea $n: responsable y justificación no pueden ser marcadores pendientes."; }
    shopt -u nocasematch
    ((${#just} >= 20)) || die2 "excepciones línea $n: la justificación técnica es demasiado corta (mínimo 20 caracteres)."
    case "$sev" in
      CRITICAL) max_days=$EXCEPTION_MAX_DAYS_CRITICAL; review_days=$EXCEPTION_REVIEW_DAYS_CRITICAL ;;
      HIGH) max_days=$EXCEPTION_MAX_DAYS_HIGH; review_days=$EXCEPTION_REVIEW_DAYS_HIGH ;;
      *) die2 "excepciones línea $n: severity debe ser CRITICAL o HIGH (recibido '$sev')." ;;
    esac
    exc_check_date "$n" approved "$approved"; exc_check_date "$n" last_review "$review"; exc_check_date "$n" expires "$expires"
    a_s=$(exc_epoch "$approved"); r_s=$(exc_epoch "$review"); e_s=$(exc_epoch "$expires")
    ((a_s <= today_s)) || die2 "excepciones línea $n: 'approved' ($approved) está en el futuro."
    ((r_s >= a_s && r_s <= today_s)) || die2 "excepciones línea $n: 'last_review' debe estar entre approved y hoy."
    ((e_s > a_s)) || die2 "excepciones línea $n: 'expires' debe ser posterior a 'approved'."
    ((e_s - a_s <= max_days * 86400)) ||
      die2 "excepciones línea $n: $id ($sev) supera el plazo máximo de $max_days días (approved $approved, expires $expires)."
    if ((today_s > e_s)); then
      printf 'AVISO excepción CADUCADA, ya no es válida y la puerta vuelve a bloquear: %s %s [%s] (expiró %s, responsable %s)\n' "$id" "$pkg" "$scope" "$expires" "$owner" >&2
      continue
    fi
    limit=$((r_s + review_days * 86400))
    if ((today_s > limit)); then
      printf 'AVISO excepción INVALIDADA por revisión vencida (cada %s días): %s %s [%s] (última revisión %s, responsable %s)\n' "$review_days" "$id" "$pkg" "$scope" "$review" "$owner" >&2
      continue
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$pkg" "$scope" "$sev" "$owner" "$just" "$approved" "$review" "$expires" >>"$EXC_VALID"
  done <"$file"
}

# exc_scope <label>: the exception scope of a scanned artifact. Images: repository name without registry, namespace or tag
# (localhost:5000/circleguard/circleguard-auth:1.2.3 -> circleguard-auth). Dependencies ("deps:<label>") keep their label.
exc_scope() {
  local label=$1
  [[ "$label" == deps:* ]] && { printf '%s' "$label"; return; }
  label=${label%%@*}; label=${label##*/}; printf '%s' "${label%%:*}"
}

# exc_matches <report.json> <scope> <blocking severities, space separated>
# Prints one line "id<TAB>package<TAB>severity<TAB>owner<TAB>expires" for every blocking finding of the report that a VALID exception covers.
exc_matches() {
  [[ -s "$EXC_VALID" ]] || return 0
  awk -F'\t' -v scope="$2" -v sevs="$3" '
    BEGIN { n = split(sevs, s, " "); for (i = 1; i <= n; i++) blocking[s[i]] = 1 }
    NR == FNR { key = $1 SUBSEP $2 SUBSEP $3 SUBSEP $4; owner[key] = $5; expd[key] = $9; next }
    /"VulnerabilityID": *"/ { id = $0; sub(/^.*"VulnerabilityID": *"/, "", id); sub(/".*$/, "", id); pkg = "" }
    /"PkgName": *"/        { pkg = $0; sub(/^.*"PkgName": *"/, "", pkg); sub(/".*$/, "", pkg) }
    /^ *"Severity": *"/    { sev = $0; sub(/^ *"Severity": *"/, "", sev); sub(/".*$/, "", sev)
                             key = id SUBSEP pkg SUBSEP scope SUBSEP sev
                             if ((sev in blocking) && (key in owner)) print id "\t" pkg "\t" sev "\t" owner[key] "\t" expd[key] }
  ' "$EXC_VALID" "$1"
}
