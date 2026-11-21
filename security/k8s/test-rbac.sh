#!/usr/bin/env bash
# HU-14 · Verifies the RBAC of a REAL cluster against security/k8s/rbac-matrix.txt using `kubectl auth can-i` with impersonation.
# Run it after applying security/k8s/rbac/ (HU-10 provides the cluster). It changes nothing in the cluster.
#
#   security/k8s/test-rbac.sh [--context <kube-context>]
#
# Requires: kubectl, and a kubeconfig identity allowed to impersonate (for example a cluster administrator).
# Exit code: 0 = every row matches; 1 = at least one row differs; 2 = usage or connection error.
set -Eeuo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MATRIX="$HERE/rbac-matrix.txt"
CTX_ARGS=()
while (($#)); do
  case "$1" in
    --context) CTX_ARGS=(--context "${2:?Falta el contexto}"); shift 2 ;;
    -h|--help) sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "ERROR: argumento desconocido $1" >&2; exit 2 ;;
  esac
done
command -v kubectl >/dev/null 2>&1 || { echo "ERROR: no está disponible kubectl" >&2; exit 2; }
kubectl "${CTX_ARGS[@]}" version >/dev/null 2>&1 || { echo "ERROR: no hay conexión con un clúster (kubectl version falló). Este script necesita el clúster de HU-10." >&2; exit 2; }

rows=0 bad=0
while read -r subject verb resource group sub namespace expected; do
  [[ -z "${subject:-}" || "$subject" == \#* ]] && continue
  rows=$((rows + 1))
  target=$resource; [[ "$group" != "-" ]] && target="$resource.$group"
  args=(auth can-i "$verb" "$target" --namespace "$namespace")
  [[ "$sub" != "-" ]] && args+=("--subresource=$sub")
  case "$subject" in
    sa:*)    ns_name=${subject#sa:}; args+=("--as=system:serviceaccount:${ns_name}") ;;
    group:*) args+=("--as=hu14-rbac-test" "--as-group=${subject#group:}") ;;
    *) echo "ERROR: sujeto desconocido $subject" >&2; exit 2 ;;
  esac
  got=$(kubectl "${CTX_ARGS[@]}" "${args[@]}" 2>/dev/null || true)
  got=${got%%$'\n'*}; [[ "$got" == yes ]] || got=no
  if [[ "$got" == "$expected" ]]; then
    printf 'PASS  %s %s %s%s in %s: %s\n' "$subject" "$verb" "$resource" "$([[ $sub != - ]] && echo "/$sub")" "$namespace" "$got"
  else
    printf 'FAIL  %s %s %s%s in %s: expected %s, got %s\n' "$subject" "$verb" "$resource" "$([[ $sub != - ]] && echo "/$sub")" "$namespace" "$expected" "$got"
    bad=$((bad + 1))
  fi
done <"$MATRIX"

printf '\nMatrix: %d of %d rows as expected\n' $((rows - bad)) "$rows"
((bad == 0)) && echo "RESULT: PASS" || { echo "RESULT: FAIL"; exit 1; }
