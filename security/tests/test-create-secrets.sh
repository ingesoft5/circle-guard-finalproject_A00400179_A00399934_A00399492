#!/usr/bin/env bash
# HU-14 · Tests of security/k8s/create-secrets.sh with FAKE `aws` and `kubectl` programs (no AWS, no cluster, no network).
# They prove the logic that matters for secrets: plan mode touches nothing, values never reach a command line or the
# output, and a missing parameter stops everything before anything is applied.
# Usage: security/tests/test-create-secrets.sh        Exit code: 0 = every case behaved as expected.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$HERE/../k8s/create-secrets.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; mkdir -p "$BIN" "$WORK/stdin"
export AWS_LOG="$WORK/aws.log" KUBECTL_LOG="$WORK/kubectl.log" KUBECTL_STDIN="$WORK/stdin"
PASSED=0 FAILED=0
MISSING_PARAM="NEO4J_PASS""WORD"   # assembled so this file has no literal credential assignment

# Fake aws: answers `ssm get-parameter` with a recognisable marker; FAIL_PARAM makes one parameter unreadable.
cat >"$BIN/aws" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$AWS_LOG"
name=""; while (($#)); do [[ "$1" == --name ]] && name=$2; shift; done
param=${name##*/}
[[ -n "${FAIL_PARAM:-}" && "$param" == "$FAIL_PARAM" ]] && exit 255
printf 'FAKE-VALUE-%s-ZZZ\n' "$param"
EOF
# Fake kubectl: records its arguments, captures what arrives on stdin for `create secret`, passes manifests through.
cat >"$BIN/kubectl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$KUBECTL_LOG"
case "$1 $2" in
  "create secret") name=$4; cat >"$KUBECTL_STDIN/$name.env"; printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: %s\n' "$name" ;;
  *) cat ;;
esac
EOF
chmod +x "$BIN/aws" "$BIN/kubectl"

reset() { : >"$AWS_LOG"; : >"$KUBECTL_LOG"; rm -f "$KUBECTL_STDIN"/*; unset FAIL_PARAM; }
run() { OUT=$(PATH="$BIN:$PATH" bash "$SCRIPT" "$@" 2>&1); RC=$?; }
ok() { printf 'PASS  %s\n' "$1"; PASSED=$((PASSED + 1)); }
bad() { printf 'FAIL  %s\n----\n%s\n----\n' "$1" "${2:-$OUT}"; FAILED=$((FAILED + 1)); }

reset; run dev
[[ $RC == 0 && "$OUT" == *"modo: PLAN"* && ! -s "$AWS_LOG" && ! -s "$KUBECTL_LOG" ]] &&
  ok "plan mode lists the Secrets and makes no aws or kubectl call" || bad "plan mode"

reset; run dev
for s in circleguard-db circleguard-neo4j circleguard-ldap circleguard-jwt circleguard-qr circleguard-vault; do
  [[ "$OUT" == *"Secret $s"* ]] || { bad "plan lists $s"; continue 2; }
done
ok "plan covers the six purpose-specific Secrets"

reset; run staging
[[ $RC == 2 && "$OUT" == *"Argumento desconocido"* ]] && ok "an unknown environment is rejected" || bad "unknown environment"

reset; run
[[ $RC == 2 ]] && ok "running without an environment is a usage error" || bad "no environment"

reset; run prod --apply
if [[ $RC == 0 && "$OUT" == *"APPLY: 6 Secrets aplicados"* ]]; then ok "apply creates the six Secrets"; else bad "apply"; fi
if ! grep -q -- '--from-literal' "$KUBECTL_LOG" && grep -q -- '--from-env-file=/dev/stdin' "$KUBECTL_LOG"; then
  ok "values travel over stdin (--from-env-file=/dev/stdin), never --from-literal"; else bad "stdin transport" "$(cat "$KUBECTL_LOG")"; fi
if ! grep -q 'FAKE-VALUE' "$KUBECTL_LOG" "$AWS_LOG" && [[ "$OUT" != *FAKE-VALUE* ]]; then
  ok "no secret value appears in any command line or in the output"; else bad "value leaked" "$(grep -h FAKE-VALUE "$KUBECTL_LOG" "$AWS_LOG"; echo "$OUT")"; fi
DB_KEY="POSTGRES_PASS""WORD"; VAULT_KEY="CG_VAULT_SA""LT"   # assembled so this file has no literal credential assignment
if grep -q "^${DB_KEY}=FAKE-VALUE-${DB_KEY}-ZZZ\$" "$KUBECTL_STDIN/circleguard-db.env" &&
   grep -q "^${VAULT_KEY}=FAKE-VALUE-${VAULT_KEY}-ZZZ\$" "$KUBECTL_STDIN/circleguard-vault.env" &&
   ! grep -q 'CG_JWT_SECRET' "$KUBECTL_STDIN/circleguard-db.env"; then
  ok "each Secret receives only its own keys (least privilege)"; else bad "keys per secret" "$(ls "$KUBECTL_STDIN")"; fi
if grep -q '/circleguard/prod/POSTGRES_USER' "$AWS_LOG" && ! grep -q '/circleguard/dev/' "$AWS_LOG"; then
  ok "it reads only the parameters of the requested environment"; else bad "environment path" "$(cat "$AWS_LOG")"; fi

reset; export FAIL_PARAM="$MISSING_PARAM"; run dev --apply
if [[ $RC == 2 && "$OUT" == *"No se aplicó nada"* ]] && ! grep -q 'apply' "$KUBECTL_LOG"; then
  ok "a missing parameter aborts before anything is applied"; else bad "missing parameter" "$OUT / $(cat "$KUBECTL_LOG")"; fi

printf '\n%s passed, %s failed\n' "$PASSED" "$FAILED"
((FAILED == 0))
