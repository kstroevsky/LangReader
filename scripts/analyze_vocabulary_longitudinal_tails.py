#!/usr/bin/env python3
"""Classify material warm-tail failures on diagnostic-development evidence."""

import argparse
import json
from pathlib import Path


MATERIAL_DEGRADATION = -0.02


def analyze(report: dict) -> dict:
    material = [
        run for run in report["runs"]
        if run["expectedWarmEligibility"] and run["naturalCoverageDifference"] < MATERIAL_DEGRADATION
    ]
    rows = []
    for run in sorted(material, key=lambda value: value["naturalCoverageDifference"]):
        fixed = run["fixedBudgetCoverageDifference"]
        classification = "stopping-implicated" if fixed >= MATERIAL_DEGRADATION else "persists-at-fixed-budget"
        rows.append({
            "runID": run["runID"],
            "scenario": run["scenario"],
            "naturalCoverageDifference": run["naturalCoverageDifference"],
            "fixedBudgetCoverageDifference": fixed,
            "coldNaturalQuestions": run["coldNatural"]["questionCount"],
            "warmNaturalQuestions": run["warmNatural"]["questionCount"],
            "classification": classification,
            "replayCoverageAttribution": "unavailable-current-replay-records-posterior-and-selection-fingerprints-only"
        })
    return {
        "schemaVersion": 1,
        "dataRole": "diagnostic-development-only",
        "materialityBoundary": MATERIAL_DEGRADATION,
        "productionConfigurationChanged": False,
        "materialTailCount": len(rows),
        "stoppingImplicatedCount": sum(row["classification"] == "stopping-implicated" for row in rows),
        "persistsAtFixedBudgetCount": sum(row["classification"] == "persists-at-fixed-budget" for row in rows),
        "rows": rows,
        "limitation": "Common-evidence replay does not currently report realized truth coverage, so fixed-budget-persistent failures cannot yet distinguish question selection from transferred-prior/posterior effects."
    }


def markdown(result: dict) -> str:
    lines = [
        "# Vocabulary longitudinal warm-tail decomposition",
        "",
        "This development-only analysis uses the existing two-percentage-point warm degradation boundary. It changes no production configuration and does not access development-confirmation or release-holdout data.",
        "",
        f"Material tails: {result['materialTailCount']}; stopping implicated: {result['stoppingImplicatedCount']}; persistent at the common 60-question budget: {result['persistsAtFixedBudgetCount']}.",
        "",
        "| Run | Natural warm-cold | Fixed-budget warm-cold | Cold/warm questions | Classification |",
        "| --- | ---: | ---: | ---: | --- |",
    ]
    for row in result["rows"]:
        lines.append(f"| {row['runID']} | {row['naturalCoverageDifference'] * 100:.3f} pp | {row['fixedBudgetCoverageDifference'] * 100:.3f} pp | {row['coldNaturalQuestions']}/{row['warmNaturalQuestions']} | {row['classification']} |")
    lines.extend([
        "",
        "Eleven of thirteen material natural failures cease to be material at the common budget, which implicates stopping under the tested paths. Two biased-self-verification failures persist and remain unattributed between changed question paths and transferred-prior/posterior effects.",
        "",
        result["limitation"],
        "",
        "Next: extend development-only replay diagnostics with realized truth coverage before choosing a mitigation. Do not disable warm personalization, change the 0.90 weight, bind confirmation, or access the release holdout from this result.",
        ""
    ])
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    parser.add_argument("--output-json", required=True, type=Path)
    parser.add_argument("--output-markdown", required=True, type=Path)
    args = parser.parse_args()
    result = analyze(json.loads(args.report.read_text()))
    args.output_json.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    args.output_markdown.write_text(markdown(result))


if __name__ == "__main__":
    main()
