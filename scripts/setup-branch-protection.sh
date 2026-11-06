#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-ingesoft5/circle-guard-finalproject_A00400179_A00399934_A00399492}"
BRANCH="${BRANCH:-main}"
CHECKS="${CHECKS:-commit-lint}"

contexts_json="$(printf '%s' "$CHECKS" | awk -v RS=',' 'BEGIN{printf "["} NR>1{printf ","} {gsub(/\n/,""); printf "\"%s\"", $0} END{printf "]"}')"

gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "repos/${REPO}/branches/${BRANCH}/protection" \
  --input - <<JSON
{
  "required_status_checks": {
    "strict": true,
    "contexts": ${contexts_json}
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
JSON

gh api "repos/${REPO}/branches/${BRANCH}/protection" \
  --jq '{checks: .required_status_checks.contexts, reviews: .required_pull_request_reviews.required_approving_review_count, admins: .enforce_admins.enabled, linear: .required_linear_history.enabled}'
