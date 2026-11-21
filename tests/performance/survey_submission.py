"""Scenario 2 (HU-15): questionnaire submission. What the client does: load the active questionnaire, answer it, submit the survey.

Measured requests (names used by targets.json):
  GET  /form/questionnaires/active   informative
  POST /form/surveys                 objective: p95, throughput and error rate

Data is synthetic: every virtual user gets a random anonymousId (no PII, no real user is touched) and answers every question NO,
so the load does not change anyone's health status and does not disturb the access scenario.
"""
import uuid
from datetime import datetime, timezone

from locust import HttpUser, constant_throughput, task

from common import float_env, target_env

target_env()
_RPS = float_env("PERF_SURVEY_RPS_PER_USER", 0.5)


class SurveySubmissionUser(HttpUser):
    wait_time = constant_throughput(_RPS)

    def on_start(self):
        self.anonymous_id = str(uuid.uuid4())
        self.question_ids = []

    @task
    def submit_survey(self):
        with self.client.get("/form/api/v1/questionnaires/active", name="GET /form/questionnaires/active",
                             catch_response=True) as active:
            if active.status_code == 200:
                try:
                    self.question_ids = [str(q["id"]) for q in active.json().get("questions", [])]
                except ValueError:
                    active.failure("the active questionnaire is not JSON")
            elif active.status_code == 404:
                active.success()  # no active questionnaire is a valid state of the service (seed it with seed_questionnaire.py)
            else:
                active.failure(f"active questionnaire returned {active.status_code}")
        payload = {
            "anonymousId": self.anonymous_id,
            "responses": {question_id: "NO" for question_id in self.question_ids} or {"synthetic": "NO"},
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        self.client.post("/form/api/v1/surveys", json=payload, name="POST /form/surveys")
