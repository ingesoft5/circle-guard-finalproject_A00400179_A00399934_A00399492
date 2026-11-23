#!/usr/bin/env bash
# Browser launcher for `aws login` (BROWSER) when the AWS CLI runs in WSL: opens the URL in the
# Windows default browser, and ONLY if it is an official AWS https address. With
# CG_BROWSER_PRIVATE=1 it uses a Microsoft Edge InPrivate window, which does not reuse a console
# session already open in the browser (for example root's).
set -euo pipefail
url=${1:-}
host=$(sed -E 's#^https://([^/:?#]+).*#\1#' <<<"$url")
if [[ "$url" != https://* || ! ("$host" == aws.amazon.com || "$host" == *.aws.amazon.com || "$host" == *.amazonaws.com) ]]; then
  echo "URL rechazada: no es una dirección oficial de AWS ($host)" >&2
  exit 1
fi
if [[ "${CG_BROWSER_PRIVATE:-}" == 1 ]]; then
  command='Start-Process msedge -ArgumentList "--inprivate", $env:CG_URL'
else
  command='Start-Process $env:CG_URL'
fi
CG_URL=$url WSLENV="CG_URL${WSLENV:+:$WSLENV}" powershell.exe -NoProfile -NonInteractive -Command "$command"
