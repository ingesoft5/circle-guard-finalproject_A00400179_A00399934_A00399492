"""Scenario 1 (HU-15): access validation. What a person does at the campus gate: have a short-lived QR token generated and validated.

Setup (once per test, not measured): ONE login of the test user, whose JWT is shared by every virtual user. Logging in per virtual user
would measure a login stampede (bcrypt on a small container) instead of the gate: in the first run 55 of 100 simultaneous logins failed
and only about 45 users generated load. The login capacity is reported separately as a finding of the report.

Measured requests (names used by targets.json):
  GET  /auth/qr/generate           informative: prerequisite of the validation
  POST /gateway/gate/validate      objective: p95, throughput and error rate

The request paths go through the web client's proxy (/auth/, /gateway/), the same route the real client uses.
"""
import time

import requests
from locust import HttpUser, constant_throughput, events, task

from common import float_env, required_env, target_env

target_env()
_RPS = float_env("PERF_ACCESS_RPS_PER_USER", 2.0)
_USERNAME = required_env("PERF_USERNAME")
_LOGIN_PW = required_env("PERF_PASSWORD")
_SHARED = {"jwt": None}


@events.test_start.add_listener
def login_once(environment, **kwargs):
    """One login for the whole test, retried while a freshly started service warms up."""
    url = environment.host.rstrip("/") + "/auth/api/v1/auth/login"
    last = "no attempt"
    for attempt in range(1, 7):
        try:
            response = requests.post(url, json={"username": _USERNAME, "password": _LOGIN_PW}, timeout=60)
            if response.status_code == 200 and "token" in response.text:
                _SHARED["jwt"] = response.json()["token"]
                return
            last = f"HTTP {response.status_code}"
        except requests.RequestException as error:
            last = type(error).__name__
        time.sleep(5 * attempt)
    environment.process_exit_code = 2
    environment.runner.quit()
    raise RuntimeError(f"the setup login failed after 6 attempts ({last}); the access scenario cannot run")


class AccessValidationUser(HttpUser):
    # Each iteration (QR + validation) is paced to PERF_ACCESS_RPS_PER_USER per second per virtual user.
    wait_time = constant_throughput(_RPS)

    @task
    def validate_access(self):
        with self.client.get("/auth/api/v1/auth/qr/generate", headers={"Authorization": f"Bearer {_SHARED['jwt']}"},
                             name="GET /auth/qr/generate", catch_response=True) as qr:
            if qr.status_code != 200 or "qrToken" not in qr.text:
                qr.failure(f"qr generate returned {qr.status_code}")
                return
            token = qr.json()["qrToken"]
        with self.client.post("/gateway/api/v1/gate/validate", json={"token": token},
                              name="POST /gateway/gate/validate", catch_response=True) as validation:
            if validation.status_code != 200:
                validation.failure(f"validate returned {validation.status_code}")
            elif not validation.json().get("valid"):
                validation.failure("the gate denied a valid token")
