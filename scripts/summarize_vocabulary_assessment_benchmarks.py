#!/usr/bin/env python3
"""Aggregate repeated vocabulary benchmark reports without hiding failed runs."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def summarize(reports: list[dict]) -> dict:
    grouped: dict[tuple[int, str, str], list[dict]] = {}
    grouped_auxiliary: dict[str, list[dict]] = {}
    for report in reports:
        for case in report["cases"]:
            key = (case["lemmaCount"], case["mode"], case.get("profile", "cold"))
            grouped.setdefault(key, []).append(case)
        for item in report.get("auxiliary", []):
            grouped_auxiliary.setdefault(item["name"], []).append(item)
    cases = []
    for (lemmas, mode, profile), values in sorted(grouped.items()):
        cases.append(
            {
                "lemmaCount": lemmas,
                "mode": mode,
                "profile": profile,
                "runCount": len(values),
                "p50RangeMS": [min(item["p50MS"] for item in values), max(item["p50MS"] for item in values)],
                "p95RangeMS": [min(item["p95MS"] for item in values), max(item["p95MS"] for item in values)],
                "maximumRangeMS": [min(item["maxMS"] for item in values), max(item["maxMS"] for item in values)],
            }
        )
    auxiliary = [
        {
            "name": name,
            "runCount": len(values),
            "p50RangeMS": [min(item["p50MS"] for item in values), max(item["p50MS"] for item in values)],
            "p95RangeMS": [min(item["p95MS"] for item in values), max(item["p95MS"] for item in values)],
        }
        for name, values in sorted(grouped_auxiliary.items())
    ]
    return {
        "schemaVersion": 1,
        "runCount": len(reports),
        "allRunsPassed": all(report["gatePassed"] for report in reports),
        "cases": cases,
        "auxiliary": auxiliary,
        "reports": reports,
    }


def markdown(summary: dict) -> str:
    lines = [
        "# Vocabulary assessment benchmark series",
        "",
        f"Runs: {summary['runCount']}; all 10,000-lemma p95 gates passed: "
        + ("yes" if summary["allRunsPassed"] else "no"),
        "",
        "| Lemmas | Mode | Profile | p50 range ms | p95 range ms | Maximum range ms |",
        "|---:|---|---|---:|---:|---:|",
    ]
    for item in summary["cases"]:
        lines.append(
            f"| {item['lemmaCount']} | {item['mode']} | {item['profile']} | "
            f"{item['p50RangeMS'][0]:.2f}–{item['p50RangeMS'][1]:.2f} | "
            f"{item['p95RangeMS'][0]:.2f}–{item['p95RangeMS'][1]:.2f} | "
            f"{item['maximumRangeMS'][0]:.2f}–{item['maximumRangeMS'][1]:.2f} |"
        )
    if summary["auxiliary"]:
        lines.extend([
            "",
            "Auxiliary phase trends (not part of the 150 ms next-card gate):",
            "",
            "| Measurement | p50 range ms | p95 range ms |",
            "|---|---:|---:|",
        ])
        for item in summary["auxiliary"]:
            lines.append(
                f"| {item['name']} | {item['p50RangeMS'][0]:.2f}–{item['p50RangeMS'][1]:.2f} | "
                f"{item['p95RangeMS'][0]:.2f}–{item['p95RangeMS'][1]:.2f} |"
            )
    lines.extend(
        [
            "",
            "The reports retain every raw sample and environment/source metadata. A failed run is not removed from the series.",
            "",
        ]
    )
    return "\n".join(lines)


def self_test() -> None:
    fixture = {
        "gatePassed": True,
        "cases": [{"lemmaCount": 10_000, "mode": "coverage-98", "profile": "cold", "p50MS": 80, "p95MS": 120, "maxMS": 130}],
    }
    failed = {
        "gatePassed": False,
        "cases": [{"lemmaCount": 10_000, "mode": "coverage-98", "profile": "cold", "p50MS": 90, "p95MS": 170, "maxMS": 220}],
        "auxiliary": [{"name": "coverage-stop-check-10000", "p50MS": 140, "p95MS": 180}],
    }
    summary = summarize([fixture, failed])
    assert summary["allRunsPassed"] is False
    assert summary["cases"][0]["p95RangeMS"] == [120, 170]
    assert summary["auxiliary"][0]["p95RangeMS"] == [180, 180]
    print("vocabulary benchmark series self-test passed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("reports", nargs="*", type=Path)
    parser.add_argument("--output-json", type=Path)
    parser.add_argument("--output-markdown", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if not args.reports:
        parser.error("provide at least one benchmark report")
    summary = summarize([json.loads(path.read_text(encoding="utf-8")) for path in args.reports])
    rendered = markdown(summary)
    if args.output_json:
        args.output_json.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if args.output_markdown:
        args.output_markdown.write_text(rendered, encoding="utf-8")
    print(rendered)
    return 0 if summary["allRunsPassed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
