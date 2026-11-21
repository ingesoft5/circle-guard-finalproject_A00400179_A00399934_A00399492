#!/usr/bin/env python3
"""HU-15 · Draws SVG charts from the Locust *_stats_history.csv files of a results directory. Standard library only.

  charts.py --results DIR --out DIR

For each <scenario>-u<users>_stats_history.csv it writes <scenario>-u<users>-latency.svg (p95 vs time, with the active users)
and <scenario>-u<users>-throughput.svg (requests/s and failures/s vs time), using the "Aggregated" rows. Then it writes
users-vs-metrics.svg: p95 and throughput of each step against the number of users.
"""
import argparse
import csv
import glob
import os
import re
import sys

W, H, PAD_L, PAD_R, PAD_T, PAD_B = 720, 320, 62, 20, 30, 44
COLORS = ["#2563eb", "#dc2626", "#16a34a", "#9333ea"]


def read_history(path):
    points = []
    with open(path, newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            if row["Name"] != "Aggregated":
                continue
            try:
                points.append({"t": int(row["Timestamp"]), "users": int(row["User Count"]), "rps": float(row["Requests/s"]),
                               "fps": float(row["Failures/s"]), "p95": float(row["95%"]) if row["95%"] not in ("", "N/A") else 0.0})
            except ValueError:
                continue
    if points:
        t0 = points[0]["t"]
        for p in points:
            p["t"] -= t0
    return points


def line_chart(title, xlabel, ylabel, series, path):
    """series: list of (label, [(x, y)])"""
    xs = [x for _, pts in series for x, _ in pts] or [0, 1]
    ys = [y for _, pts in series for _, y in pts] or [0, 1]
    x0, x1 = min(xs), max(xs) or 1
    y1 = max(ys) * 1.1 or 1

    def px(x):
        return PAD_L + (x - x0) / ((x1 - x0) or 1) * (W - PAD_L - PAD_R)

    def py(y):
        return H - PAD_B - y / y1 * (H - PAD_T - PAD_B)

    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" font-family="sans-serif" font-size="11">',
           f'<rect width="{W}" height="{H}" fill="white"/>',
           f'<text x="{W / 2}" y="18" text-anchor="middle" font-size="13" font-weight="bold">{title}</text>']
    for i in range(5):
        y = y1 * i / 4
        out.append(f'<line x1="{PAD_L}" x2="{W - PAD_R}" y1="{py(y):.1f}" y2="{py(y):.1f}" stroke="#e5e7eb"/>')
        out.append(f'<text x="{PAD_L - 6}" y="{py(y) + 4:.1f}" text-anchor="end">{y:.0f}</text>')
    for i in range(5):
        x = x0 + (x1 - x0) * i / 4
        out.append(f'<text x="{px(x):.1f}" y="{H - PAD_B + 16}" text-anchor="middle">{x:.0f}</text>')
    out.append(f'<text x="{W / 2}" y="{H - 6}" text-anchor="middle">{xlabel}</text>')
    out.append(f'<text x="14" y="{H / 2}" text-anchor="middle" transform="rotate(-90 14 {H / 2})">{ylabel}</text>')
    for k, (label, pts) in enumerate(series):
        color = COLORS[k % len(COLORS)]
        if len(pts) > 1:
            out.append(f'<polyline fill="none" stroke="{color}" stroke-width="2" points="{" ".join(f"{px(x):.1f},{py(y):.1f}" for x, y in pts)}"/>')
        else:
            out += [f'<circle cx="{px(x):.1f}" cy="{py(y):.1f}" r="3" fill="{color}"/>' for x, y in pts]
        out.append(f'<rect x="{PAD_L + 8 + k * 150}" y="{PAD_T - 4}" width="10" height="10" fill="{color}"/>')
        out.append(f'<text x="{PAD_L + 22 + k * 150}" y="{PAD_T + 5}">{label}</text>')
    out.append("</svg>")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(out))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--results", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)
    steps = []
    for path in sorted(glob.glob(os.path.join(args.results, "*_stats_history.csv"))):
        match = re.match(r"^(.+)-u(\d+)_stats_history\.csv$", os.path.basename(path))
        points = read_history(path)
        if not match or not points:
            continue
        stem = f"{match[1]}-u{match[2]}"
        line_chart(f"{match[1]} · {match[2]} usuarios · latencia p95", "segundos", "ms",
                   [("p95 (ms)", [(p["t"], p["p95"]) for p in points]), ("usuarios", [(p["t"], p["users"]) for p in points])],
                   os.path.join(args.out, f"{stem}-latency.svg"))
        line_chart(f"{match[1]} · {match[2]} usuarios · throughput", "segundos", "req/s",
                   [("req/s", [(p["t"], p["rps"]) for p in points]), ("fallos/s", [(p["t"], p["fps"]) for p in points])],
                   os.path.join(args.out, f"{stem}-throughput.svg"))
        steady = points[len(points) // 4:] or points
        steps.append((match[1], int(match[2]), max(p["p95"] for p in steady), sum(p["rps"] for p in steady) / len(steady)))
    if not steps:
        print("no *_stats_history.csv found; no charts written", file=sys.stderr)
        return 2
    by_scenario = {}
    for scenario, users, p95, rps in steps:
        by_scenario.setdefault(scenario, []).append((users, p95, rps))
    series = []
    for scenario, items in sorted(by_scenario.items()):
        items.sort()
        series.append((f"{scenario} p95 (ms)", [(u, p) for u, p, _ in items]))
        series.append((f"{scenario} req/s", [(u, r) for u, _, r in items]))
    line_chart("p95 y throughput frente a usuarios", "usuarios", "ms o req/s", series, os.path.join(args.out, "users-vs-metrics.svg"))
    print(f"charts written to {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
