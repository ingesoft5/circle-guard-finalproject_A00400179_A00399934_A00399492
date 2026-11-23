#!/usr/bin/env python3
"""HU-15 · Builds the numbers of the consolidated report (performance, ZAP, test coverage and quality) as one Markdown fragment.
Standard library only. Every input is optional; a missing one is reported as "no disponible", never invented.

  consolidate.py --perf DIR/evaluation.json --zap DIR/zap-report.json [--jacoco-dir DIR --junit-dir DIR ...] [--out FILE]

--jacoco-dir  a directory searched recursively for jacocoTestReport.xml (one per service): line and branch coverage per service
--junit-dir   a directory searched recursively for JUnit XML files (TEST-*.xml): tests, failures, errors and skipped, per suite directory
"""
import argparse
import glob
import json
import os
import sys
import xml.etree.ElementTree as ET


def perf_section(path):
    if not path or not os.path.exists(path):
        return ["_Resultados de rendimiento: no disponibles._", ""]
    result = json.load(open(path, encoding="utf-8"))
    lines = ["| Solicitud | Usuarios | p95 (ms) | Throughput (req/s) | Errores (%) | Cumple |", "|---|---|---|---|---|---|"]
    for r in result["rows"]:
        if r["target"] is None:
            continue
        checks = [v for v in r["checks"].values() if v is not None]
        verdict = "sí" if all(checks) else "no"
        lines.append(f"| {r['name']} | {r['users']} | {r['p95_ms']:.0f} | {r['rps']:.1f} | {r['error_pct']:.2f} | {verdict} |")
    lines += ["", "Veredicto por objetivo (escalón de referencia): " + "; ".join(f"{k}: **{v}**" for k, v in result["verdicts"].items()), ""]
    return lines


def zap_section(path):
    if not path or not os.path.exists(path):
        return ["_Resultados de ZAP: no disponibles._", ""]
    text = open(path, encoding="utf-8").read()
    doc = json.loads(text)
    counts = {"3": 0, "2": 0, "1": 0, "0": 0}
    rows = []
    for site in doc.get("site", []):
        for alert in site.get("alerts", []):
            counts[alert["riskcode"]] = counts.get(alert["riskcode"], 0) + 1
            rows.append((alert["riskcode"], alert["alert"], alert.get("count", "?")))
    names = {"3": "High", "2": "Medium", "1": "Low", "0": "Informational"}
    lines = ["| Riesgo | Alertas distintas |", "|---|---|"] + [f"| {names[k]} | {counts[k]} |" for k in ("3", "2", "1", "0")]
    lines += ["", "| Riesgo | Alerta | Instancias |", "|---|---|---|"]
    lines += [f"| {names[r]} | {n} | {c} |" for r, n, c in sorted(rows, key=lambda x: (-int(x[0]), x[1]))]
    return lines + [""]


def jacoco_section(directory):
    if not directory:
        return ["_Cobertura JaCoCo: no disponible._", ""]
    rows, totals = [], {"LINE": [0, 0], "BRANCH": [0, 0]}
    for path in sorted(glob.glob(os.path.join(directory, "**", "jacocoTestReport.xml"), recursive=True)):
        service = next((p for p in path.split(os.sep) if p.startswith("circleguard-")), os.path.basename(os.path.dirname(path)))
        root = ET.parse(path).getroot()
        values = {}
        for counter in root.findall("counter"):
            if counter.get("type") in totals:
                missed, covered = int(counter.get("missed")), int(counter.get("covered"))
                values[counter.get("type")] = (missed, covered)
                totals[counter.get("type")][0] += missed
                totals[counter.get("type")][1] += covered
        def pct(kind):
            m, c = values.get(kind, (0, 0))
            return f"{100.0 * c / (m + c):.1f} %" if m + c else "n/a"
        rows.append(f"| {service} | {pct('LINE')} | {pct('BRANCH')} |")
    if not rows:
        return ["_Cobertura JaCoCo: no se encontraron informes._", ""]
    def total(kind):
        m, c = totals[kind]
        return f"{100.0 * c / (m + c):.1f} %" if m + c else "n/a"
    return ["| Servicio | Líneas | Ramas |", "|---|---|---|"] + rows + [f"| **Total** | **{total('LINE')}** | **{total('BRANCH')}** |", ""]


def junit_section(directories):
    if not directories:
        return ["_Pruebas ejecutadas: no disponibles._", ""]
    lines = ["| Suite | Pruebas | Fallos | Errores | Omitidas |", "|---|---|---|---|---|"]
    grand = [0, 0, 0, 0]
    for directory in directories:
        t = f = e = s = 0
        for path in glob.glob(os.path.join(directory, "**", "TEST-*.xml"), recursive=True):
            root = ET.parse(path).getroot()
            t += int(root.get("tests", 0)); f += int(root.get("failures", 0)); e += int(root.get("errors", 0)); s += int(root.get("skipped", 0))
        parts = os.path.normpath(directory).split(os.sep)
        owner = next((p for p in parts if p.startswith("circleguard-") or p in ("integration", "e2e-playwright")), parts[-1])
        kind = parts[-1]
        lines.append(f"| {owner} ({kind}) | {t} | {f} | {e} | {s} |")
        grand = [grand[0] + t, grand[1] + f, grand[2] + e, grand[3] + s]
    lines.append(f"| **Total** | **{grand[0]}** | **{grand[1]}** | **{grand[2]}** | **{grand[3]}** |")
    return lines + [""]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--perf")
    parser.add_argument("--zap")
    parser.add_argument("--jacoco-dir")
    parser.add_argument("--junit-dir", action="append", default=[])
    parser.add_argument("--out")
    args = parser.parse_args(argv)
    try:
        lines = (["### Rendimiento", ""] + perf_section(args.perf) + ["### Seguridad dinámica (OWASP ZAP baseline)", ""] + zap_section(args.zap) +
                 ["### Cobertura de pruebas (JaCoCo)", ""] + jacoco_section(args.jacoco_dir) +
                 ["### Pruebas ejecutadas (JUnit)", ""] + junit_section(args.junit_dir))
    except (OSError, ValueError, KeyError, ET.ParseError) as exc:
        print(f"ERROR: cannot read an input: {exc!r}", file=sys.stderr)
        return 2
    text = "\n".join(lines)
    print(text)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as handle:
            handle.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
