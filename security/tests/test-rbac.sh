#!/usr/bin/env bash
# HU-14 · Tests of the RBAC tooling (security/k8s/rbac-check.py and security/k8s/test-rbac.sh). No cluster, no network.
#  - rbac-check.py must PASS on the real manifests and FAIL on deliberately unsafe copies (so it is known to detect problems).
#  - test-rbac.sh is exercised with a FAKE kubectl, to check how it builds the impersonation calls and how it reacts to a mismatch.
# Requires PyYAML for the first part. Usage: security/tests/test-rbac.sh    Exit code: 0 = every case behaved as expected.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
K8S="$HERE/../k8s"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PASSED=0 FAILED=0
ok() { printf 'PASS  %s\n' "$1"; PASSED=$((PASSED + 1)); }
bad() { printf 'FAIL  %s\n----\n%s\n----\n' "$1" "${2:-}"; FAILED=$((FAILED + 1)); }

python3 -c "import yaml" 2>/dev/null || { echo "SKIP: PyYAML is not installed (pip install pyyaml)"; exit 0; }

check_manifests() { # check_manifests <dir> -> sets OUT, RC
  OUT=$(python3 -I "$K8S/rbac-check.py" "$1" "$K8S/rbac-matrix.txt" 2>&1); RC=$?
}

check_manifests "$K8S/rbac"
if [[ $RC == 0 && "$OUT" == *"RESULT: PASS"* ]]; then ok "the real manifests pass the lint and the whole matrix"; else bad "real manifests" "$OUT"; fi

mutant() { # mutant <name> <sed expression on roles.yaml> ; copies the manifests and edits roles.yaml
  rm -rf "$WORK/$1" && cp -r "$K8S/rbac" "$WORK/$1" && sed -i "$2" "$WORK/$1/roles.yaml"
}

mutant wildcard 's/verbs: \["get", "create", "update", "patch"\]/verbs: ["*"]/'
check_manifests "$WORK/wildcard"
[[ $RC == 1 && "$OUT" == *"wildcard in verbs"* ]] && ok "a wildcard verb is detected" || bad "wildcard" "$OUT"

mutant secretlist 's/verbs: \["get", "create", "update", "patch"\]/verbs: ["get", "list", "delete", "create"]/'
check_manifests "$WORK/secretlist"
[[ $RC == 1 && "$OUT" == *"on secrets"* ]] && ok "list/delete on secrets is detected" || bad "secret list" "$OUT"

mutant deployer-secrets 's/resources: \["services", "configmaps", "serviceaccounts"\]/resources: ["services", "configmaps", "serviceaccounts", "secrets"]/'
check_manifests "$WORK/deployer-secrets"
[[ $RC == 1 && "$OUT" == *"FAIL  sa:circleguard:jenkins-deployer get secrets"* ]] && ok "giving the deployer access to secrets breaks the matrix" || bad "deployer secrets" "$OUT"

rm -rf "$WORK/clusteradmin" && cp -r "$K8S/rbac" "$WORK/clusteradmin" && sed -i 's/name: circleguard-deployer$/name: cluster-admin/' "$WORK/clusteradmin/rolebindings.yaml"
check_manifests "$WORK/clusteradmin"
[[ $RC == 1 && "$OUT" == *"broad built-in role"* ]] && ok "binding a broad built-in role (cluster-admin) is detected" || bad "cluster-admin" "$OUT"

rm -rf "$WORK/automount" && cp -r "$K8S/rbac" "$WORK/automount" && sed -i '0,/automountServiceAccountToken: false/s//automountServiceAccountToken: true/' "$WORK/automount/serviceaccounts.yaml"
check_manifests "$WORK/automount"
[[ $RC == 1 && "$OUT" == *"automountServiceAccountToken must be false"* ]] && ok "a ServiceAccount that mounts its token is detected" || bad "automount" "$OUT"

# --- the live script, with a fake kubectl
BIN="$WORK/bin"; mkdir -p "$BIN"; export KLOG="$WORK/kubectl.log"
cat >"$BIN/kubectl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$KLOG"
[[ "$1" == version ]] && exit 0
# FAKE_DENY_ALL=1: answer "no" to everything; FAKE_ALLOW_ALL=1: answer "yes" to everything; otherwise answer from the matrix
if [[ -n "${FAKE_ALLOW_ALL:-}" ]]; then echo yes; exit 0; fi
echo no; exit 1
EOF
chmod +x "$BIN/kubectl"

: >"$KLOG"; OUT=$(PATH="$BIN:$PATH" FAKE_ALLOW_ALL=1 bash "$K8S/test-rbac.sh" 2>&1); RC=$?
[[ $RC == 1 && "$OUT" == *"RESULT: FAIL"* && "$OUT" == *"expected no, got yes"* ]] && ok "the live script fails when the cluster allows what the matrix denies" || bad "live mismatch" "$OUT"
grep -q -- '--as=system:serviceaccount:circleguard:jenkins-deployer' "$KLOG" &&
  grep -q 'deployments.apps' "$KLOG" && grep -q -- '--subresource=log' "$KLOG" && grep -q -- '--as-group=circleguard-viewers' "$KLOG" &&
  ok "it impersonates ServiceAccounts and groups and passes group and subresource correctly" || bad "impersonation arguments" "$(head -5 "$KLOG")"

: >"$KLOG"; OUT=$(PATH="$BIN:$PATH" bash "$K8S/test-rbac.sh" 2>&1); RC=$?
[[ $RC == 1 && "$OUT" == *"expected yes, got no"* ]] && ok "the live script fails when the cluster denies what the matrix allows" || bad "live mismatch (deny)" "$OUT"

# --namespace: the environment namespace of HU-10 replaces the placeholder in the subject and in the namespace column
: >"$KLOG"; PATH="$BIN:$PATH" FAKE_ALLOW_ALL=1 bash "$K8S/test-rbac.sh" --namespace circleguard-stage >/dev/null 2>&1
grep -q -- '--as=system:serviceaccount:circleguard-stage:jenkins-deployer' "$KLOG" && grep -q -- '--namespace circleguard-stage' "$KLOG" &&
  ! grep -q -- '--namespace circleguard$' "$KLOG" && ! grep -q -- 'serviceaccount:circleguard:' "$KLOG" &&
  ok "--namespace rewrites the placeholder namespace for the subject and the namespace column" || bad "--namespace rewrite" "$(head -4 "$KLOG")"
grep -q -- '--namespace observability' "$KLOG" && grep -q -- '--namespace kube-system' "$KLOG" &&
  ok "other namespaces of the matrix (observability, kube-system) are checked as written" || bad "other namespaces" "$(head -4 "$KLOG")"

# the three overlays set the HU-10 namespaces and keep the contract intact (kustomize is not needed: they are plain declarations)
for env in dev stage prod; do
  grep -q "^namespace: circleguard-$env$" "$K8S/rbac-overlays/$env/kustomization.yaml" && grep -q '^  - ../../rbac$' "$K8S/rbac-overlays/$env/kustomization.yaml" &&
    ok "overlay $env targets namespace circleguard-$env" || bad "overlay $env" "$(cat "$K8S/rbac-overlays/$env/kustomization.yaml" 2>&1)"
done

# the pods have no rights: the matrix must say so for the default ServiceAccount
grep -q '^sa:circleguard:default *get *secrets .* no$' "$K8S/rbac-matrix.txt" && ok "the matrix checks that the default ServiceAccount cannot read secrets" || bad "default SA rows" "missing"

OUT=$(PATH="/usr/bin:/bin" bash "$K8S/test-rbac.sh" 2>&1); RC=$?
[[ $RC == 2 ]] && ok "without kubectl or a cluster it reports an error (exit 2), never a pass" || bad "no kubectl" "$OUT"

printf '\n%s passed, %s failed\n' "$PASSED" "$FAILED"
((FAILED == 0))
