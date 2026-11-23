#!/usr/bin/env python3
"""HU-14 · Offline check of the Kubernetes RBAC manifests (no cluster needed).

It (1) lints the manifests for risky patterns and (2) evaluates every row of rbac-matrix.txt with the RBAC rules of the
manifests, using the same matching as Kubernetes: a request is allowed if some Role/ClusterRole bound to the subject has a rule
whose apiGroups, resources and verbs match. Anything not granted is denied (RBAC is additive; there are no deny rules).

IT IS A SIMULATION. It proves that the manifests say what the contract says; it does NOT prove that RBAC is applied in a cluster.
The real check is security/k8s/test-rbac.sh (`kubectl auth can-i`) once a cluster exists.

usage: rbac-check.py [manifest-dir] [matrix-file]     requires PyYAML     exit code: 0 = all good, 1 = a violation or a mismatch
"""
import glob
import os
import sys

import yaml

here = os.path.dirname(os.path.abspath(__file__))
manifest_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "rbac")
matrix_file = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, "rbac-matrix.txt")

docs = []
for path in sorted(glob.glob(os.path.join(manifest_dir, "*.y*ml"))):
    with open(path, encoding="utf-8") as f:
        docs += [(path, d) for d in yaml.safe_load_all(f) if d]

roles = {}          # (namespace or None, name) -> rules
bindings = []       # (namespace or None, roleRef kind, roleRef name, subjects)
service_accounts = []
problems = []

for path, d in docs:
    kind, meta = d.get("kind"), d.get("metadata", {})
    ns, name = meta.get("namespace"), meta.get("name")
    where = f"{os.path.basename(path)}:{kind}/{name}"
    if kind in ("Role", "ClusterRole"):
        roles[(ns if kind == "Role" else None, name)] = d.get("rules", [])
        if kind == "ClusterRole":
            problems.append(f"{where}: a ClusterRole is not expected here (namespaced Roles only)")
        for rule in d.get("rules", []):
            for field in ("verbs", "resources", "apiGroups"):
                if "*" in rule.get(field, []):
                    problems.append(f"{where}: wildcard in {field}")
            verbs, res = set(rule.get("verbs", [])), set(rule.get("resources", []))
            if "secrets" in res and verbs & {"list", "watch", "delete", "deletecollection"}:
                problems.append(f"{where}: grants {sorted(verbs & {'list', 'watch', 'delete', 'deletecollection'})} on secrets")
            if verbs & {"escalate", "bind", "impersonate"}:
                problems.append(f"{where}: grants {sorted(verbs & {'escalate', 'bind', 'impersonate'})}")
            if res & {"pods/exec", "pods/attach", "nodes", "nodes/proxy"}:
                problems.append(f"{where}: grants {sorted(res & {'pods/exec', 'pods/attach', 'nodes', 'nodes/proxy'})}")
    elif kind in ("RoleBinding", "ClusterRoleBinding"):
        ref = d.get("roleRef", {})
        bindings.append((ns if kind == "RoleBinding" else None, ref.get("kind"), ref.get("name"), d.get("subjects", [])))
        if kind == "ClusterRoleBinding":
            problems.append(f"{where}: a ClusterRoleBinding is not expected here")
        if ref.get("name") in ("cluster-admin", "admin", "edit"):
            problems.append(f"{where}: binds the broad built-in role {ref.get('name')}")
        for s in d.get("subjects", []):
            if s.get("kind") == "User":
                problems.append(f"{where}: bound to an individual user ({s.get('name')}); bind groups or ServiceAccounts")
    elif kind == "ServiceAccount":
        service_accounts.append(d)
        if meta.get("name") != "default" and d.get("automountServiceAccountToken") is not False:
            problems.append(f"{where}: automountServiceAccountToken must be false")
        if name == "default":
            problems.append(f"{where}: do not configure the default ServiceAccount; use one per service")


def subject_matches(s, subject, namespace):
    kind, _, rest = subject.partition(":")
    if kind == "sa":
        sa_ns, _, sa_name = rest.partition(":")
        return s.get("kind") == "ServiceAccount" and s.get("name") == sa_name and s.get("namespace", namespace) == sa_ns
    return s.get("kind") == "Group" and s.get("name") == rest


def allowed(subject, verb, resource, group, sub, namespace):
    full = resource + ("/" + sub if sub != "-" else "")
    grp = "" if group == "-" else group
    for b_ns, ref_kind, ref_name, subjects in bindings:
        if b_ns is not None and b_ns != namespace:
            continue                                    # a RoleBinding only applies inside its own namespace
        if not any(subject_matches(s, subject, b_ns) for s in subjects):
            continue
        for rule in roles.get((b_ns if ref_kind == "Role" else None, ref_name), []):
            if (verb in rule.get("verbs", []) or "*" in rule.get("verbs", [])) and \
               (full in rule.get("resources", []) or "*" in rule.get("resources", [])) and \
               (grp in rule.get("apiGroups", []) or "*" in rule.get("apiGroups", [])):
                return True
    return False


print(f"Manifests: {len(docs)} objects in {manifest_dir}")
print(f"Lint: {'no findings' if not problems else str(len(problems)) + ' finding(s)'}")
for p in problems:
    print(f"  VIOLATION  {p}")

mismatches = rows = 0
with open(matrix_file, encoding="utf-8") as f:
    for number, line in enumerate(f, 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        subject, verb, resource, group, sub, namespace, expected = line.split()
        rows += 1
        got = "yes" if allowed(subject, verb, resource, group, sub, namespace) else "no"
        status = "PASS" if got == expected else "FAIL"
        if status == "FAIL":
            mismatches += 1
        label = f"{subject} {verb} {resource}{'/' + sub if sub != '-' else ''} in {namespace}"
        print(f"  {status}  {label}: expected {expected}, got {got}")

print(f"\nMatrix: {rows - mismatches} of {rows} rows as expected")
ok = not problems and mismatches == 0 and rows > 0
print("RESULT: PASS" if ok else "RESULT: FAIL")
sys.exit(0 if ok else 1)
