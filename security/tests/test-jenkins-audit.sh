#!/usr/bin/env bash
# HU-14 · Tests of security/audit-jenkins-credentials.sh with small pipeline snippets (no Jenkins, no Docker, no network).
# The credentials in the snippets are obviously fictitious and live only in a temporary directory.
# Usage: security/tests/test-jenkins-audit.sh        Exit code: 0 = every case behaved as expected.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
AUDIT="$HERE/../audit-jenkins-credentials.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PASSED=0 FAILED=0

# case <description> <expected exit code> <expected text> <<< pipeline snippet
case_() {
  local desc=$1 want_rc=$2 want_text=$3 file="$WORK/Jenkinsfile.$PASSED.$FAILED" out rc
  cat >"$file"
  out=$(bash "$AUDIT" "$file" 2>&1); rc=$?
  if [[ "$rc" == "$want_rc" && "$out" == *"$want_text"* ]]; then
    printf 'PASS  %s (exit %s)\n' "$desc" "$rc"; PASSED=$((PASSED + 1))
  else
    printf 'FAIL  %s: expected exit %s with "%s", got exit %s\n----\n%s\n----\n' "$desc" "$want_rc" "$want_text" "$rc" "$out"; FAILED=$((FAILED + 1))
  fi
}

case_ "a pipeline that only uses withCredentials and shell expansion passes" 0 "PASS" <<'EOF'
withCredentials([usernamePassword(credentialsId: 'registry', usernameVariable: 'REG_USER', passwordVariable: 'REG_PASSWORD')]) {
  sh 'docker login -u "$REG_USER" -p "$REG_PASSWORD" registry.example.invalid'
  sh "./deploy/publish.sh '${env.VERSION}'"
}
EOF

case_ "a literal password in the pipeline is a violation" 1 "posible credencial" <<'EOF'
def password = 'FAKE-literal-0000'
EOF

case_ "Groovy interpolation of a secret in a double-quoted sh is a violation" 1 "interpolada por Groovy" <<'EOF'
withCredentials([string(credentialsId: 'gh', variable: 'GITHUB_TOKEN')]) {
  sh "curl -H 'Authorization: token ${GITHUB_TOKEN}' https://api.example.invalid"
}
EOF

case_ "a credential inside a URL is a violation" 1 "dentro de una URL" <<'EOF'
sh 'git clone https://ci-user:FAKEvalue@git.example.invalid/repo.git'
EOF

case_ "printing a secret variable is only a warning" 0 "se imprime" <<'EOF'
withCredentials([string(credentialsId: 'gh', variable: 'GITHUB_TOKEN')]) {
  echo "token is $GITHUB_TOKEN"
}
EOF

case_ "credentials() in environment{} is only a warning" 0 "credentials() en environment" <<'EOF'
pipeline { environment { DEPLOY_KEY = credentials('deploy-key') } }
EOF

case_ "a commented-out example is ignored" 0 "PASS" <<'EOF'
// def password = 'FAKE-commented-0000'
EOF

printf '\n%s passed, %s failed\n' "$PASSED" "$FAILED"
((FAILED == 0))
