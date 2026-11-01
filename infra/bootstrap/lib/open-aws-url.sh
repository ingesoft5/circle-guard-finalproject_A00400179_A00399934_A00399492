#!/usr/bin/env bash
# Browser launcher for `aws login` (BROWSER) when the AWS CLI runs in WSL: opens the URL in the
# Windows default browser, and ONLY if it is an official AWS https address.
set -euo pipefail
url=${1:-}
host=$(sed -E 's#^https://([^/:?#]+).*#\1#' <<<"$url")
if [[ "$url" != https://* || ! ("$host" == aws.amazon.com || "$host" == *.aws.amazon.com || "$host" == *.amazonaws.com) ]]; then
  echo "URL rechazada: no es una dirección oficial de AWS ($host)" >&2
  exit 1
fi
CG_URL=$url WSLENV="CG_URL${WSLENV:+:$WSLENV}" powershell.exe -NoProfile -NonInteractive -Command 'Start-Process $env:CG_URL'
