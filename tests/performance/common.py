"""Shared settings of the HU-15 Locust scenarios. Everything comes from the environment: no value is hard coded.

PERF_TARGET_ENV       local | dev | stage. Anything else (prod above all) is refused: these tests never run against production.
PERF_USERNAME         user of the environment under test (a seeded test user). Required by the access scenario.
PERF_PASSWORD         its password. Never written to a file or printed.
PERF_ACCESS_RPS_PER_USER   iterations per second of each access user (default 2.0 -> 100 users offer 200 validations/s)
PERF_SURVEY_RPS_PER_USER   submissions per second of each survey user (default 0.5 -> 100 users offer 50 submissions/s)
"""
import os
import sys

ALLOWED_ENVS = ("local", "dev", "stage")


def target_env() -> str:
    env = os.environ.get("PERF_TARGET_ENV", "").strip().lower()
    if env not in ALLOWED_ENVS:
        sys.stderr.write(
            f"ERROR: PERF_TARGET_ENV must be one of {', '.join(ALLOWED_ENVS)} (got '{env}'). "
            "The performance tests never run against production.\n")
        sys.exit(2)
    return env


def float_env(name: str, default: float) -> float:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    try:
        value = float(raw)
    except ValueError:
        sys.stderr.write(f"ERROR: {name} must be a number (got '{raw}').\n")
        sys.exit(2)
    if value <= 0:
        sys.stderr.write(f"ERROR: {name} must be greater than 0.\n")
        sys.exit(2)
    return value


def required_env(name: str) -> str:
    value = os.environ.get(name, "")
    if not value:
        sys.stderr.write(f"ERROR: {name} is required (set it in the environment; it is not stored anywhere).\n")
        sys.exit(2)
    return value
