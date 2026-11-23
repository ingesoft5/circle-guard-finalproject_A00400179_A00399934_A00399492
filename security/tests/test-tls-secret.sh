#!/usr/bin/env bash
# HU-14 · Tests of security/k8s/tls/ensure-tls-secret.sh. Offline: a FAKE kubectl records what it receives, openssl is real.
# It checks that the Secret holds a valid certificate for the requested host whose key matches, that the key never appears in a process
# argument, that the temporary directory is removed, and that bad input is rejected before anything is generated.
# Needs openssl. Usage: security/tests/test-tls-secret.sh      Exit code: 0 = every case behaved as expected.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$HERE/../k8s/tls/ensure-tls-secret.sh"
command -v openssl >/dev/null 2>&1 || { echo "SKIP: openssl is not installed"; exit 0; }
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; mkdir -p "$BIN" "$WORK/tmp"
export KLOG="$WORK/kubectl.log" KSECRET="$WORK/applied.yaml" TMPDIR="$WORK/tmp"
PASSED=0 FAILED=0
ok() { printf 'PASS  %s\n' "$1"; PASSED=$((PASSED + 1)); }
bad() { printf 'FAIL  %s\n----\n%s\n----\n' "$1" "${2:-}"; FAILED=$((FAILED + 1)); }

# Fake kubectl: logs its arguments; `create secret tls` emits the Secret manifest built from the given files; `apply` stores stdin;
# `get secret` answers 0 (exists) only when FAKE_EXISTS=1.
cat >"$BIN/kubectl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$KLOG"
case "$*" in
  *"get secret"*) [[ "${FAKE_EXISTS:-}" == 1 ]] && exit 0 || exit 1 ;;
  *"create secret tls"*)
    for a in "$@"; do case "$a" in --cert=*) c=${a#--cert=} ;; --key=*) k=${a#--key=} ;; esac; done
    printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: circleguard-tls\ntype: kubernetes.io/tls\ndata:\n  tls.crt: %s\n  tls.key: %s\n' "$(base64 -w0 "$c")" "$(base64 -w0 "$k")" ;;
  *apply*) cat >"$KSECRET" ;;
esac
EOF
chmod +x "$BIN/kubectl"
run() { PATH="$BIN:$PATH" bash "$SCRIPT" "$@" 2>&1; }

: >"$KLOG"; rm -f "$KSECRET"
OUT=$(run dev --host 203.0.113.10); RC=$?
[[ $RC == 0 && "$OUT" == *PLAN* && ! -s "$KLOG" ]] && ok "the default is a PLAN: no certificate, no cluster call" || bad "plan" "$OUT"

: >"$KLOG"; rm -f "$KSECRET"
OUT=$(run dev --host 203.0.113.10 --days 30 --apply); RC=$?
[[ $RC == 0 && -s "$KSECRET" ]] && ok "--apply creates and applies the Secret" || bad "apply" "$OUT"
grep -q -- '-n circleguard-dev' "$KLOG" && ok "the namespace defaults to circleguard-<env>" || bad "namespace" "$(cat "$KLOG")"
grep -q '^type: kubernetes.io/tls$' "$KSECRET" && ok "the Secret is of type kubernetes.io/tls" || bad "type" "$(cat "$KSECRET")"

sed -n 's/^  tls.crt: //p' "$KSECRET" | base64 -d >"$WORK/crt.pem"; sed -n 's/^  tls.key: //p' "$KSECRET" | base64 -d >"$WORK/key.pem"
openssl x509 -in "$WORK/crt.pem" -noout -ext subjectAltName 2>/dev/null | grep -q '203.0.113.10' && ok "the certificate is valid for the requested IP (SAN)" || bad "SAN" "$(openssl x509 -in "$WORK/crt.pem" -noout -text 2>&1 | head -30)"
[[ "$(openssl x509 -in "$WORK/crt.pem" -noout -pubkey | openssl sha256)" == "$(openssl pkey -in "$WORK/key.pem" -pubout | openssl sha256)" ]] && ok "the private key matches the certificate" || bad "key pair" "mismatch"
openssl x509 -in "$WORK/crt.pem" -noout -checkend $((29 * 86400)) >/dev/null && ! openssl x509 -in "$WORK/crt.pem" -noout -checkend $((31 * 86400)) >/dev/null &&
  ok "--days sets the validity (30 days)" || bad "validity" "$(openssl x509 -in "$WORK/crt.pem" -noout -enddate)"
key_body=$(grep -v -- '-----' "$WORK/key.pem" | head -1)
! grep -q -F "$key_body" "$KLOG" && ok "the private key never appears in a process argument" || bad "key in argv" "found"
[[ -z "$(ls -A "$TMPDIR")" ]] && ok "the temporary directory with the key is removed" || bad "temp leftovers" "$(ls -A "$TMPDIR")"

: >"$KLOG"; rm -f "$KSECRET"
OUT=$(run stage --host circleguard.example.invalid --namespace custom-ns --apply)
openssl x509 -in <(sed -n 's/^  tls.crt: //p' "$KSECRET" | base64 -d) -noout -ext subjectAltName 2>/dev/null | grep -q 'DNS:circleguard.example.invalid' && grep -q -- '-n custom-ns' "$KLOG" &&
  ok "a DNS name works, and --namespace overrides the default" || bad "dns/namespace" "$OUT"

: >"$KLOG"; rm -f "$KSECRET"
OUT=$(FAKE_EXISTS=1 run dev --host 203.0.113.10 --apply)
[[ ! -s "$KSECRET" && "$OUT" == *"ya existe"* ]] && ok "an existing Secret is left alone" || bad "existing" "$OUT"
rm -f "$KSECRET"; OUT=$(FAKE_EXISTS=1 run dev --host 203.0.113.10 --apply --renew)
[[ -s "$KSECRET" ]] && ok "--renew replaces an existing Secret" || bad "renew" "$OUT"

for evil in 'x;rm -rf /' '$(id)' 'a b' '' '999.1.1' 'bad_host!'; do
  : >"$KLOG"
  OUT=$(run dev --host "$evil" --apply); RC=$?
  [[ $RC == 2 && ! -s "$KLOG" ]] && ok "invalid host '$evil' is rejected before anything runs" || bad "host '$evil'" "rc=$RC $OUT"
done
OUT=$(run dev --host 203.0.113.10 --days 9999 --apply); [[ $? == 2 ]] && ok "an absurd validity is rejected" || bad "days" "$OUT"
OUT=$(run prod --apply); [[ $? == 2 ]] && ok "without --host it is an error" || bad "no host" "$OUT"
OUT=$(run qa --host 203.0.113.10); [[ $? == 2 ]] && ok "an unknown environment is an error" || bad "env" "$OUT"

printf '\n%s passed, %s failed\n' "$PASSED" "$FAILED"
((FAILED == 0))
