"""HU-15 · Offline tests of evaluate.py (objectives vs. Locust results) and charts.py, with synthetic Locust CSV files.
Run: python3 tests/performance/tests/test_evaluate.py        (standard library only; no Locust, no Docker, no network)
"""
import contextlib
import csv
import io
import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import charts  # noqa: E402
import evaluate  # noqa: E402

TARGETS = os.path.join(os.path.dirname(HERE), "targets.json")
STATS_COLUMNS = ["Type", "Name", "Request Count", "Failure Count", "Median Response Time", "Average Response Time", "Min Response Time",
                 "Max Response Time", "Average Content Size", "Requests/s", "Failures/s", "50%", "66%", "75%", "80%", "90%", "95%",
                 "98%", "99%", "99.9%", "99.99%", "100%"]
HISTORY_COLUMNS = ["Timestamp", "User Count", "Type", "Name", "Requests/s", "Failures/s", "50%", "95%"]


def stats_row(name, count, failures, p50, p95, rps):
    row = dict.fromkeys(STATS_COLUMNS, "0")
    row.update({"Type": "POST", "Name": name, "Request Count": str(count), "Failure Count": str(failures), "Median Response Time": str(p50),
                "Max Response Time": str(p95 * 2), "Requests/s": str(rps), "50%": str(p50), "95%": str(p95), "99%": str(p95 * 1.5)})
    return row


def write_stats(directory, scenario, users, rows):
    with open(os.path.join(directory, f"{scenario}-u{users}_stats.csv"), "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=STATS_COLUMNS)
        writer.writeheader()
        writer.writerows(rows)


def run(directory, *extra):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        rc = evaluate.main(["--targets", TARGETS, "--results", directory, *extra])
    return rc, out.getvalue() + err.getvalue()


GATE = "POST /gateway/gate/validate"
FORM = "POST /form/surveys"


class EvaluateTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = self._tmp.name

    def tearDown(self):
        self._tmp.cleanup()

    def both(self, gate, form, users=100):
        write_stats(self.dir, "access", users, [stats_row(GATE, *gate)])
        write_stats(self.dir, "survey", users, [stats_row(FORM, *form)])

    def test_every_objective_met(self):
        self.both(gate=(60000, 0, 40, 250, 210.0), form=(15000, 10, 300, 700, 52.0))
        rc, out = run(self.dir, "--enforce")
        self.assertEqual(rc, 0, out)
        self.assertIn("RESULT: MET", out)

    def test_p95_over_the_objective_is_not_met(self):
        self.both(gate=(60000, 0, 40, 301, 210.0), form=(15000, 10, 300, 700, 52.0))
        rc, out = run(self.dir, "--enforce")
        self.assertEqual(rc, 1, out)
        self.assertIn("NOT MET", out)

    def test_error_rate_over_the_objective_is_not_met(self):
        self.both(gate=(1000, 11, 40, 250, 210.0), form=(1000, 10, 300, 700, 52.0))  # 1.1 % > 1 %
        self.assertEqual(run(self.dir, "--enforce")[0], 1)

    def test_throughput_under_the_objective_in_the_reference_step_is_not_met(self):
        self.both(gate=(60000, 0, 40, 250, 199.9), form=(15000, 10, 300, 700, 52.0))
        self.assertEqual(run(self.dir, "--enforce")[0], 1)

    def test_not_met_without_enforce_is_report_only(self):
        self.both(gate=(60000, 0, 40, 400, 210.0), form=(15000, 10, 300, 700, 52.0))
        rc, out = run(self.dir)
        self.assertEqual(rc, 0)
        self.assertIn("NOT MET", out)

    def test_values_exactly_on_the_objective_are_met(self):
        self.both(gate=(1000, 10, 40, 300, 200.0), form=(1000, 20, 300, 800, 50.0))  # 1.0 % and 2.0 % exactly
        self.assertEqual(run(self.dir, "--enforce")[0], 0)

    def test_throughput_is_not_judged_in_smaller_steps(self):
        self.both(gate=(60000, 0, 40, 250, 210.0), form=(15000, 10, 300, 700, 52.0))
        write_stats(self.dir, "access", 10, [stats_row(GATE, 5000, 0, 30, 120, 20.0)])  # 20 req/s offered, far below 200
        rc, out = run(self.dir, "--enforce")
        self.assertEqual(rc, 0, out)
        self.assertIn("n/a", out)

    def test_missing_reference_step_is_an_error_never_a_pass(self):
        write_stats(self.dir, "access", 10, [stats_row(GATE, 5000, 0, 30, 120, 20.0)])
        rc, out = run(self.dir, "--enforce")
        self.assertEqual(rc, 2, out)
        self.assertIn("NOT MEASURED", out)

    def test_a_scenario_that_was_not_run_does_not_hide_the_others(self):
        write_stats(self.dir, "access", 100, [stats_row(GATE, 60000, 0, 40, 250, 210.0)])
        rc, out = run(self.dir, "--enforce")
        self.assertEqual(rc, 0, out)
        self.assertIn("NOT RUN", out)

    def test_no_results_is_an_error(self):
        rc, out = run(self.dir)
        self.assertEqual(rc, 2)

    def test_a_request_without_traffic_counts_as_all_errors(self):
        self.both(gate=(0, 0, 0, 0, 0.0), form=(15000, 10, 300, 700, 52.0))
        self.assertEqual(run(self.dir, "--enforce")[0], 1)

    def test_writes_json_and_markdown(self):
        self.both(gate=(60000, 0, 40, 250, 210.0), form=(15000, 10, 300, 700, 52.0))
        out_json, out_md = os.path.join(self.dir, "e.json"), os.path.join(self.dir, "e.md")
        run(self.dir, "--out-json", out_json, "--out-md", out_md)
        self.assertEqual(json.load(open(out_json))["verdicts"][GATE], "MET")
        self.assertIn("p95", open(out_md, encoding="utf-8").read())

    def test_the_objectives_match_the_declared_document(self):
        targets = json.load(open(TARGETS, encoding="utf-8"))["targets"]
        self.assertEqual((targets[GATE]["p95_ms"], targets[GATE]["min_rps"], targets[GATE]["max_error_pct"]), (300, 200, 1.0))
        self.assertEqual((targets[FORM]["p95_ms"], targets[FORM]["min_rps"], targets[FORM]["max_error_pct"]), (800, 50, 2.0))


class ChartsTest(unittest.TestCase):
    def test_draws_the_svg_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            with open(os.path.join(tmp, "access-u10_stats_history.csv"), "w", newline="", encoding="utf-8") as handle:
                writer = csv.DictWriter(handle, fieldnames=HISTORY_COLUMNS)
                writer.writeheader()
                for i in range(12):
                    writer.writerow({"Timestamp": 1000 + i, "User Count": 10, "Type": "", "Name": "Aggregated", "Requests/s": 20 + i,
                                     "Failures/s": 0, "50%": 20, "95%": 100 + i})
            out = os.path.join(tmp, "charts")
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(charts.main(["--results", tmp, "--out", out]), 0)
            names = sorted(os.listdir(out))
            self.assertEqual(names, ["access-u10-latency.svg", "access-u10-throughput.svg", "users-vs-metrics.svg"])
            self.assertTrue(open(os.path.join(out, names[0]), encoding="utf-8").read().startswith("<svg"))


if __name__ == "__main__":
    unittest.main(verbosity=1)
