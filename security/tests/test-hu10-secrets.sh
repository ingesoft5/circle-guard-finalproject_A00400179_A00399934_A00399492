#!/usr/bin/env bash
# HU-14 · Tests that the secret handling of HU-10 (deploy/k8s/secrets.sh and the ECR pull secret of deploy/k8s/deploy.sh) never puts a
# secret value in a process argument (visible in `ps` and in /proc to every user of the host). FAKE aws and kubectl record their arguments
# and standard input; no AWS or cluster call is made. Needs python3 (to read the JSON the scripts produce) and base64.
# Usage: security/tests/test-hu10-secrets.sh      Exit code: 0 = every case behaved as expected.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 is not installed"; exit 0; }
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; mkdir -p "$BIN"
export ALOG="$WORK/aws.log" KLOG="$WORK/kubectl.log" STDIN_DIR="$WORK/stdin"; mkdir -p "$STDIN_DIR"
TOKEN="ECRTOKEN$RANDOM$RANDOM"          # fictitious ECR token
PASSED=0 FAILED=0
ok() { printf 'PASS  %s\n' "$1"; PASSED=$((PASSED + 1)); }
bad() { printf 'FAIL  %s\n----\n%s\n----\n' "$1" "${2:-}"; FAILED=$((FAILED + 1)); }

# fake aws: logs argv; keeps stdin of put-parameter; get-parameter of app-secrets fails unless FAKE_PARAM_EXISTS is set
cat >"$BIN/aws" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$ALOG"
case "$*" in
  *"sts get-caller-identity"*) echo 123456789012 ;;
  *"ecr get-login-password"*) printf '%s' "$FAKE_ECR_TOKEN" ;;
  *"ssm put-parameter"*) cat >"$STDIN_DIR/put-parameter.json" ;;
  *"ssm get-parameter"*app-secrets*) [[ -n "${FAKE_PARAM_EXISTS:-}" ]] && printf 'POSTGRES_USER=circleguard\nPOSTGRES_PASSWORD=existing\n' || exit 254 ;;
  *"ssm get-parameter"*kubeconfig*) echo "apiVersion: v1" ;;
esac
EOF
# fake kubectl: logs argv; keeps stdin of every piped command in a numbered file; `kustomize` prints a tiny manifest
cat >"$BIN/kubectl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$KLOG"
n=$(ls "$STDIN_DIR" | wc -l)
case "$*" in
  *kustomize*) printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: x\ndata:\n  image: __REGISTRY__/a:__TAG__\n' ;;
  *"create secret"*) if [[ "$*" == *"--from-env-file=/dev/stdin"* || "$*" == *"--from-file=.dockerconfigjson=/dev/stdin"* ]]; then cat >"$STDIN_DIR/create-secret-$n.txt"; fi; printf 'kind: Secret\n' ;;
  *apply*) cat >"$STDIN_DIR/apply-$n.txt" ;;
esac
exit 0
EOF
chmod +x "$BIN/aws" "$BIN/kubectl"
export FAKE_ECR_TOKEN="$TOKEN"

# ------------------------------------------------------------------ deploy/k8s/secrets.sh
: >"$ALOG"; : >"$KLOG"; rm -f "$STDIN_DIR"/*
OUT=$(PATH="$BIN:$PATH" bash "$ROOT/deploy/k8s/secrets.sh" dev 2>&1); RC=$?
[[ $RC == 0 && "$OUT" == *"generados y guardados en SSM"* ]] && ok "secrets.sh generates the secrets and stores them in SSM" || bad "secrets.sh run" "rc=$RC $OUT"
python3 -I - "$STDIN_DIR/put-parameter.json" >"$WORK/put.out" 2>&1 <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
keys = [l.split("=", 1)[0] for l in lines]
assert keys == ["POSTGRES_USER", "POSTGRES_PASSWORD", "NEO4J_PASSWORD", "LDAP_ADMIN_PASSWORD", "CG_JWT_SECRET", "CG_QR_SECRET", "CG_VAULT_SECRET", "CG_VAULT_SALT", "CG_VAULT_HASH_SALT"], keys
assert all(len(l.split("=", 1)[1]) >= 16 for l in lines[1:]), "a generated secret is too short"
sys.stdout.write("\n".join(l.split("=", 1)[1] for l in lines[1:]))
PY
[[ -s "$WORK/put.out" && "$(head -c 5 "$WORK/put.out")" != Trace ]] && ok "the value sent to SSM has the 9 keys of the catalog, each generated secret at least 16 characters" || bad "put-parameter stdin" "$(cat "$WORK/put.out")"
leaked=0; while IFS= read -r v; do [[ -n "$v" ]] && grep -q -F -- "$v" "$ALOG" "$KLOG" && leaked=1; done <"$WORK/put.out"
((leaked == 0)) && ok "no generated secret value appears in any aws or kubectl argument" || bad "values in argv" "$(cat "$ALOG")"
grep -q -- '--value file:///dev/stdin' "$ALOG" && grep -q -- '--type SecureString' "$ALOG" && ok "put-parameter reads the value from stdin (--value file:///dev/stdin) as a SecureString" || bad "--value" "$(cat "$ALOG")"
[[ "$OUT" != *"$(head -1 "$WORK/put.out")"* ]] && ok "no secret value is printed" || bad "stdout leak" "$OUT"
grep -q -- '--from-env-file=/dev/stdin' "$KLOG" && ok "the Kubernetes Secret is created from stdin" || bad "from-env-file" "$(cat "$KLOG")"

: >"$ALOG"; : >"$KLOG"; rm -f "$STDIN_DIR"/*
OUT=$(FAKE_PARAM_EXISTS=1 PATH="$BIN:$PATH" bash "$ROOT/deploy/k8s/secrets.sh" stage 2>&1)
[[ "$OUT" == *"leídos desde SSM"* && ! -e "$STDIN_DIR/put-parameter.json" ]] && ok "existing secrets are read, never regenerated or overwritten" || bad "existing" "$OUT"

# ------------------------------------------------------------------ deploy/k8s/deploy.sh (ECR pull secret)
: >"$ALOG"; : >"$KLOG"; rm -f "$STDIN_DIR"/*
OUT=$(KUBECONFIG="$WORK/kubeconfig" FAKE_PARAM_EXISTS=1 PATH="$BIN:$PATH" bash "$ROOT/deploy/k8s/deploy.sh" dev 0.3.0 2>&1); RC=$?
[[ $RC == 0 ]] && ok "deploy.sh runs to the end with the fake tools" || bad "deploy.sh run" "rc=$RC $OUT"
! grep -q -F "$TOKEN" "$ALOG" "$KLOG" && ok "the ECR token never appears in an aws or kubectl argument" || bad "token in argv" "$(grep -F "$TOKEN" "$ALOG" "$KLOG")"
! grep -q -- '--docker-password' "$KLOG" && grep -q -- '--type=kubernetes.io/dockerconfigjson' "$KLOG" && ok "the pull secret is a dockerconfigjson created from stdin, not --docker-password" || bad "docker-password" "$(grep ecr-pull "$KLOG")"
f=$(grep -l -F "$TOKEN" "$STDIN_DIR"/create-secret-* 2>/dev/null | head -1)
if [[ -n "$f" ]]; then
  python3 -I - "$f" "$TOKEN" "123456789012.dkr.ecr.us-east-2.amazonaws.com" <<'PY' && ok "the dockerconfigjson on stdin is valid and its auth decodes to AWS:<token>" || bad "dockerconfigjson" "$(cat "$f")"
import base64, json, sys
d = json.load(open(sys.argv[1]))
e = d["auths"][sys.argv[3]]
assert e["username"] == "AWS" and e["password"] == sys.argv[2]
assert base64.b64decode(e["auth"]).decode() == "AWS:" + sys.argv[2]
PY
else bad "dockerconfigjson on stdin" "not found"; fi
grep -q -E '^-n circleguard-dev apply|apply -f -' "$KLOG" && ok "the manifests are still applied (registry and tag rendered)" || bad "apply" "$(cat "$KLOG")"
grep -q -E 'rollout status' "$KLOG" && ok "it still waits for the rollouts" || bad "rollout" "$(cat "$KLOG")"

printf '\n%s passed, %s failed\n' "$PASSED" "$FAILED"
((FAILED == 0))
