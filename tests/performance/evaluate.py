#!/usr/bin/env python3
"""HU-15 · Compares Locust results with the declared objectives (targets.json). Standard library only.

  evaluate.py --targets targets.json --results DIR [--out-json FILE] [--out-md FILE] [--enforce]

DIR holds the Locust --csv outputs, one set per step, named <scenario>-u<USERS>_stats.csv (for example access-u100_stats.csv).
For every step and every target request it reports p95 latency, throughput (requests/s) and error rate, and checks them:
  - p95 and error rate are checked in every step;
  - throughput is checked only in the reference step (users == reference_users): in the smaller steps the offered load is
    smaller than the objective by design, so a lower throughput there is not a failure.
Verdict: MET only when every target was measured in the reference step and all three of its objectives hold.

Exit code: 0 = every objective met (or --enforce not given and some not met), 1 = --enforce and an objective was not met,
2 = data missing or unreadable (a target that was not measured is never a pass).
"""
import argparse
import csv
import glob
import json
import os
import re
import sys

STEP_RE = re.compile(r"^(?P<scenario>.+)-u(?P<users>\d+)_stats\.csv$")


def read_stats(path):
    rows = {}
    with open(path, newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            rows[row["Name"]] = row
    return rows


def metrics(row):
    count = int(float(row["Request Count"]))
    failures = int(float(row["Failure Count"]))
    return {
        "requests": count,
        "failures": failures,
        "error_pct": (100.0 * failures / count) if count else 100.0,
        "p50_ms": float(row["50%"]),
        "p95_ms": float(row["95%"]),
        "p99_ms": float(row["99%"]),
        "max_ms": float(row["Max Response Time"]),
        "rps": float(row["Requests/s"]),
    }


def load_steps(results_dir):
    steps = []
    for path in sorted(glob.glob(os.path.join(results_dir, "*_stats.csv"))):
        match = STEP_RE.match(os.path.basename(path))
        if match:
            steps.append((match["scenario"], int(match["users"]), read_stats(path)))
    return steps


def evaluate(targets_doc, steps):
    reference = int(targets_doc["reference_users"])
    out = {"reference_users": reference, "rows": [], "verdicts": {}}
    names = list(targets_doc["targets"]) + list(targets_doc.get("informative", []))
    for scenario, users, stats in steps:
        for name in names:
            if name not in stats:
                continue
            m = metrics(stats[name])
            target = targets_doc["targets"].get(name)
            row = {"scenario": scenario, "users": users, "name": name, "target": target, **m, "checks": {}}
            if target:
                row["checks"]["p95"] = m["p95_ms"] <= target["p95_ms"]
                row["checks"]["errors"] = m["error_pct"] <= target["max_error_pct"]
                row["checks"]["throughput"] = (m["rps"] >= target["min_rps"]) if users == reference else None
            out["rows"].append(row)
    ran = {scenario for scenario, _, _ in steps}
    for name, target in targets_doc["targets"].items():
        ref_rows = [r for r in out["rows"] if r["name"] == name and r["users"] == reference]
        if target.get("scenario") not in ran:
            out["verdicts"][name] = "NOT RUN"
        elif not ref_rows:
            out["verdicts"][name] = "NOT MEASURED"
        else:
            checks = ref_rows[-1]["checks"]
            out["verdicts"][name] = "MET" if all(v for v in checks.values() if v is not None) and checks["throughput"] is not None else "NOT MET"
    return out


def render_markdown(result):
    lines = ["| Solicitud | Usuarios | Peticiones | p50 (ms) | p95 (ms) | Objetivo p95 | Throughput (req/s) | Objetivo | Errores (%) | Objetivo | Veredicto |",
             "|---|---|---|---|---|---|---|---|---|---|---|"]

    def mark(ok):
        return "n/a" if ok is None else ("cumple" if ok else "NO cumple")

    for r in result["rows"]:
        t = r["target"]
        if t:
            verdict = f"p95 {mark(r['checks']['p95'])} · throughput {mark(r['checks']['throughput'])} · errores {mark(r['checks']['errors'])}"
            lines.append(f"| {r['name']} | {r['users']} | {r['requests']} | {r['p50_ms']:.0f} | {r['p95_ms']:.0f} | ≤ {t['p95_ms']} | "
                         f"{r['rps']:.1f} | ≥ {t['min_rps']} | {r['error_pct']:.2f} | ≤ {t['max_error_pct']} | {verdict} |")
        else:
            lines.append(f"| {r['name']} (informativa) | {r['users']} | {r['requests']} | {r['p50_ms']:.0f} | {r['p95_ms']:.0f} | — | "
                         f"{r['rps']:.1f} | — | {r['error_pct']:.2f} | — | — |")
    lines += ["", f"Veredicto por objetivo (en el escalón de referencia de {result['reference_users']} usuarios):", ""]
    lines += [f"- **{name}**: {verdict}" for name, verdict in result["verdicts"].items()]
    return "\n".join(lines) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--targets", required=True)
    parser.add_argument("--results", required=True)
    parser.add_argument("--out-json")
    parser.add_argument("--out-md")
    parser.add_argument("--enforce", action="store_true")
    args = parser.parse_args(argv)
    try:
        with open(args.targets, encoding="utf-8") as handle:
            targets_doc = json.load(handle)
        steps = load_steps(args.results)
    except (OSError, ValueError, KeyError) as exc:
        print(f"ERROR: cannot read the inputs: {exc}", file=sys.stderr)
        return 2
    if not steps:
        print(f"ERROR: no <scenario>-u<users>_stats.csv in {args.results}", file=sys.stderr)
        return 2
    try:
        result = evaluate(targets_doc, steps)
    except (KeyError, ValueError) as exc:
        print(f"ERROR: unexpected result format: {exc!r}", file=sys.stderr)
        return 2
    markdown = render_markdown(result)
    print(markdown)
    if args.out_json:
        with open(args.out_json, "w", encoding="utf-8") as handle:
            json.dump(result, handle, indent=2)
    if args.out_md:
        with open(args.out_md, "w", encoding="utf-8") as handle:
            handle.write(markdown)
    verdicts = result["verdicts"].values()
    if any(v == "NOT MEASURED" for v in verdicts):
        print("RESULT: ERROR · an objective was not measured in the reference step", file=sys.stderr)
        return 2
    if any(v == "NOT MET" for v in verdicts):
        print("RESULT: NOT MET · at least one objective was not met" + ("" if args.enforce else " (report only, --enforce not given)"))
        return 1 if args.enforce else 0
    if all(v == "NOT RUN" for v in verdicts):
        print("RESULT: ERROR · no scenario of the targets was run", file=sys.stderr)
        return 2
    skipped = [n for n, v in result["verdicts"].items() if v == "NOT RUN"]
    print("RESULT: MET · every objective that was run was met" + (f" (not run: {', '.join(skipped)})" if skipped else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
