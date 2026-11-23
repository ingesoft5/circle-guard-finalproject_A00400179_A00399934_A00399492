"""HU-15 · Locust entry point. Pick the scenario by class name:

  locust -f tests/performance/locustfile.py AccessValidationUser --host http://web:8080 --users 100 --spawn-rate 10 --run-time 5m --headless
  locust -f tests/performance/locustfile.py SurveySubmissionUser --host http://web:8080 ...

Users, spawn rate and duration are Locust's own options; the per-user request rate is PERF_ACCESS_RPS_PER_USER / PERF_SURVEY_RPS_PER_USER
(see common.py). Prefer tests/performance/run-perf.sh, which runs the scenario in a pinned container, in steps, and evaluates the result.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

_scenario = os.environ.get("PERF_SCENARIO", "").strip().lower()
if _scenario in ("access", ""):
    from access_validation import AccessValidationUser  # noqa: F401
if _scenario in ("survey", ""):
    from survey_submission import SurveySubmissionUser  # noqa: F401
