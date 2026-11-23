#!/usr/bin/env bash
# HU-14 · Tests of security/k8s/fetch-kubeconfig.sh with a FAKE aws CLI (no AWS call). Checks that it reads the right SSM parameter,
# writes a private file (mode 600), prints only the path, never prints the content, never overwrites, and fails cleanly.
# Usage: security/tests/test-fetch-kubeconfig.sh      Exit code: 0 = every case behaved as expected.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$HERE/../k8s/fetch-kubeconfig.sh"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; mkdir -p "$BIN" "$WORK/tmp"
export ALOG="$WORK/aws.log" TMPDIR="$WORK/tmp"
MARKER="FAKE-KUBECONFIG-CONTENT-$RANDOM"   # a fictitious value standing for the kubeconfig
export FAKE_VALUE="apiVersion: v1\nkind: Config\nusers:\n- name: fake\n  user: {token: $MARKER}"
PASSED=0 FAILED=0
ok() { printf 'PASS  %s\n' "$1"; PASSED=$((PASSED + 1)); }
bad() { printf 'FAIL  %s\n----\n%s\n----\n' "$1" "${2:-}"; FAILED=$((FAILED + 1)); }

cat >"$BIN/aws" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$ALOG"
[[ "${FAKE_AWS_FAIL:-}" == 1 ]] && { echo "AccessDeniedException" >&2; exit 254; }
[[ "${FAKE_AWS_EMPTY:-}" == 1 ]] && exit 0
printf '%b\n' "$FAKE_VALUE"
EOF
chmod +x "$BIN/aws"
run() { PATH="$BIN:$PATH" bash "$SCRIPT" "$@"; }

: >"$ALOG"
STDOUT=$(run dev 2>"$WORK/stderr"); RC=$?
[[ $RC == 0 && -f "$STDOUT" ]] && ok "it writes a file and prints its path" || bad "path" "rc=$RC out=$STDOUT"
[[ "$(stat -c %a "$STDOUT" 2>/dev/null)" == 600 ]] && ok "the file is private (mode 600)" || bad "mode" "$(stat -c %a "$STDOUT")"
grep -q -F "$MARKER" "$STDOUT" && ok "the file holds the content of the parameter" || bad "content" "$(cat "$STDOUT")"
[[ "$STDOUT" != *"$MARKER"* && "$(cat "$WORK/stderr")" != *"$MARKER"* ]] && ok "the content is never printed (stdout is only the path, stderr has no content)" || bad "leak" "$(cat "$WORK/stderr")"
grep -q -- '--name /circleguard/dev/kubeconfig' "$ALOG" && grep -q -- '--with-decryption' "$ALOG" && grep -q -- 'ssm get-parameter' "$ALOG" &&
  ok "it reads /circleguard/<env>/kubeconfig with decryption" || bad "parameter name" "$(cat "$ALOG")"
[[ "$(wc -l <"$ALOG")" == 1 ]] && ! grep -q -E 'put-|delete-|create-|update-' "$ALOG" && ok "exactly one read-only AWS call" || bad "calls" "$(cat "$ALOG")"
! grep -q -F "$MARKER" "$ALOG" && ok "the content never appears in a process argument" || bad "argv" "$(cat "$ALOG")"

: >"$ALOG"; OUT_FILE="$WORK/own-kubeconfig"
STDOUT=$(run prod --out "$OUT_FILE" 2>/dev/null)
[[ "$STDOUT" == "$OUT_FILE" && "$(stat -c %a "$OUT_FILE")" == 600 ]] && grep -q -- '/circleguard/prod/kubeconfig' "$ALOG" && ok "--out writes where asked, for the requested environment" || bad "--out" "$STDOUT"

OUT=$(run prod --out "$OUT_FILE" 2>&1); RC=$?
[[ $RC == 2 && "$OUT" == *"no se sobrescribe"* ]] && ok "an existing file is never overwritten" || bad "overwrite" "rc=$RC $OUT"

before=$(ls -A "$TMPDIR" | wc -l)
OUT=$(FAKE_AWS_FAIL=1 run dev 2>&1); RC=$?
[[ $RC == 2 && "$OUT" == *"No se pudo leer"* && "$(ls -A "$TMPDIR" | wc -l)" == "$before" ]] && ok "an AWS error is exit 2 and leaves no file behind" || bad "aws failure" "rc=$RC $OUT"
OUT=$(FAKE_AWS_EMPTY=1 run dev 2>&1); RC=$?
[[ $RC == 2 && "$OUT" == *"vacío"* ]] && ok "an empty parameter is an error" || bad "empty" "rc=$RC $OUT"

OUT=$(run 2>&1); [[ $? == 2 ]] && ok "without an environment it is an error" || bad "no env" "$OUT"
OUT=$(run qa 2>&1); [[ $? == 2 ]] && ok "an unknown environment is an error" || bad "unknown env" "$OUT"
OUT=$(run dev --out 2>&1); [[ $? == 2 ]] && ok "--out without a value is an error" || bad "--out empty" "$OUT"
OUT=$(PATH="/usr/bin:/bin" bash "$SCRIPT" dev 2>&1); RC=$?
[[ $RC == 2 && "$OUT" == *"AWS CLI"* ]] && ok "without the AWS CLI it reports an error" || bad "no aws" "rc=$RC $OUT"

printf '\n%s passed, %s failed\n' "$PASSED" "$FAILED"
((FAILED == 0))
