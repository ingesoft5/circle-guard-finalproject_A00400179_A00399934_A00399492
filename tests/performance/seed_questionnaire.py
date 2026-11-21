#!/usr/bin/env python3
"""HU-15 · Makes sure the environment under test has an ACTIVE questionnaire, so the survey scenario submits against a real one.
Idempotent: if there is already an active questionnaire it does nothing. Standard library only.

  PERF_TARGET_ENV=local seed_questionnaire.py http://web:8080

Only local, dev or stage (see common.py). It creates one synthetic questionnaire ("HU-15 performance questionnaire", YES_NO questions).
Exit code: 0 = there is an active questionnaire, 2 = it could not be created.
"""
import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import target_env  # noqa: E402


def call(method, url, body=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read()
            return response.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as error:
        return error.code, None


def main():
    target_env()
    if len(sys.argv) != 2:
        print("usage: seed_questionnaire.py <base url>", file=sys.stderr)
        return 2
    base = sys.argv[1].rstrip("/") + "/form/api/v1/questionnaires"
    status, active = call("GET", base + "/active")
    if status == 200 and active:
        print("an active questionnaire already exists; nothing to do")
        return 0
    questions = [{"text": text, "type": "YES_NO", "orderIndex": i} for i, text in
                 enumerate(["Do you have fever?", "Do you have a cough?", "Did you have contact with a confirmed case?"], start=1)]
    status, created = call("POST", base, {"title": "HU-15 performance questionnaire", "description": "Synthetic, for load tests",
                                          "version": 1, "isActive": False, "questions": questions})
    if status != 200 or not created or "id" not in created:
        print(f"could not create the questionnaire (HTTP {status})", file=sys.stderr)
        return 2
    status, _ = call("POST", f"{base}/{created['id']}/activate")
    if status != 200:
        print(f"could not activate the questionnaire (HTTP {status})", file=sys.stderr)
        return 2
    print("synthetic questionnaire created and activated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
