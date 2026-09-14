#!/usr/bin/env python3
"""Summarize the frozen current-document compatibility development run."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def mean(values):
    return sum(values) / len(values) if values else 0.0


def summarize(rows, coverage_key, reduction_key):
    coverage = [coverage_key(row) for row in rows]
    reductions = [reduction_key(row) for row in rows]
    return {
        "meanCoverageDifference": mean(coverage),
        "worstCoverageDifference": min(coverage),
        "materialTailCount": sum(value < -0.02 for value in coverage),
        "meanQuestionReduction": mean(reductions),
    }


def analyze(report, reservation):
    rows = report["runs"]
    expected_count = reservation["workload"]["plannedEligibleRuns"]
    if len(rows) != expected_count:
        raise ValueError("retained row count does not match the frozen workload")
    eligible = [row for row in rows if row["expectedWarmEligibility"]]
    production = summarize(
        eligible,
        lambda row: row["naturalCoverageDifference"],
        lambda row: row["naturalQuestionReduction"],
    )
    candidate = summarize(
        eligible,
        lambda row: row["warmCompatibility"]["candidateCoverageDifference"],
        lambda row: row["warmCompatibility"]["candidateQuestionReduction"],
    )
    decision = reservation["decisionRule"]
    gate_results = {
        "materialTailCount": candidate["materialTailCount"] <= decision["maximumMaterialTailCount"],
        "meanCoverageDifference": (
            candidate["meanCoverageDifference"] >= decision["minimumMeanWarmMinusColdCoverage"]
        ),
        "meanQuestionReduction": (
            candidate["meanQuestionReduction"] >= decision["minimumMeanQuestionReduction"]
        ),
    }
    production_tails = {
        row["runID"] for row in eligible
        if row["naturalCoverageDifference"] < decision["materialCoverageDegradation"]
    }
    candidate_tails = {
        row["runID"] for row in eligible
        if row["warmCompatibility"]["candidateCoverageDifference"]
        < decision["materialCoverageDegradation"]
    }
    scenario_rows = []
    for scenario in reservation["workload"]["scenarios"]:
        selected = [row for row in eligible if row["scenario"] == scenario]
        scenario_rows.append({
            "scenario": scenario,
            "eligibleRuns": len(selected),
            "production": summarize(
                selected,
                lambda row: row["naturalCoverageDifference"],
                lambda row: row["naturalQuestionReduction"],
            ),
            "candidate": summarize(
                selected,
                lambda row: row["warmCompatibility"]["candidateCoverageDifference"],
                lambda row: row["warmCompatibility"]["candidateQuestionReduction"],
            ),
        })
    supported = sum(
        row["warmCompatibility"].get("supportsEightQuestionMinimum") is True
        for row in eligible
    )
    rejected = sum(
        row["warmCompatibility"].get("supportsEightQuestionMinimum") is False
        for row in eligible
    )
    no_decision = len(eligible) - supported - rejected
    return {
        "schemaVersion": 1,
        "dataRole": "diagnostic-development-only",
        "productionConfigurationChanged": False,
        "retainedRuns": len(rows),
        "eligibleRuns": len(eligible),
        "ineligibleRuns": len(rows) - len(eligible),
        "signalSupport": {
            "supported": supported,
            "rejected": rejected,
            "noDecision": no_decision,
            "counterfactualMinimumApplied": sum(
                row["warmCompatibility"]["counterfactualMinimumApplied"]
                for row in eligible
            ),
        },
        "productionBaseline": production,
        "compatibilityCandidate": candidate,
        "materialTailsEliminated": len(production_tails - candidate_tails),
        "materialTailsIntroduced": len(candidate_tails - production_tails),
        "gateResults": gate_results,
        "candidatePass": all(gate_results.values()),
        "scenarioResults": scenario_rows,
        "decision": (
            "reject-candidate-retain-production"
            if not all(gate_results.values())
            else "candidate-eligible-for-separate-production-review"
        ),
        "limitation": (
            "Synthetic deterministic learner draws and a conditional warm-selected validation signal "
            "do not establish real-learner safety or confirmatory non-inferiority."
        ),
    }


def markdown(result):
    baseline = result["productionBaseline"]
    candidate = result["compatibilityCandidate"]
    lines = [
        "# Vocabulary warm compatibility development result",
        "",
        "This is the single frozen development execution. It changes no production configuration and does not access development-confirmation or release-holdout data.",
        "",
        f"Retained rows: {result['retainedRuns']}; eligible: {result['eligibleRuns']}; ineligible: {result['ineligibleRuns']}.",
        "",
        "| Policy | Mean warm-cold coverage | Worst warm-cold coverage | Material tails | Mean question reduction |",
        "| --- | ---: | ---: | ---: | ---: |",
        f"| Production count-only relaxation | {baseline['meanCoverageDifference'] * 100:.4f} pp | {baseline['worstCoverageDifference'] * 100:.4f} pp | {baseline['materialTailCount']} | {baseline['meanQuestionReduction'] * 100:.3f}% |",
        f"| Frozen likelihood-ratio candidate | {candidate['meanCoverageDifference'] * 100:.4f} pp | {candidate['worstCoverageDifference'] * 100:.4f} pp | {candidate['materialTailCount']} | {candidate['meanQuestionReduction'] * 100:.3f}% |",
        "",
        f"The signal supported relaxation for {result['signalSupport']['supported']} eligible rows, rejected it for {result['signalSupport']['rejected']}, had insufficient validation support for {result['signalSupport']['noDecision']}, and applied the 20-question counterfactual to {result['signalSupport']['counterfactualMinimumApplied']} rows.",
        "",
        f"It eliminated {result['materialTailsEliminated']} previous material tails and introduced {result['materialTailsIntroduced']}. The predeclared material-tail gate {'passed' if result['gateResults']['materialTailCount'] else 'failed'}; the mean-coverage gate {'passed' if result['gateResults']['meanCoverageDifference'] else 'failed'}; the question-reduction gate {'passed' if result['gateResults']['meanQuestionReduction'] else 'failed'}.",
        "",
        f"Decision: **{result['decision']}**. The zero threshold must not be tuned from this consumed result.",
        "",
        result["limitation"],
        "",
    ]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    parser.add_argument("reservation", type=Path)
    parser.add_argument("--output-json", required=True, type=Path)
    parser.add_argument("--output-markdown", required=True, type=Path)
    args = parser.parse_args()
    report = json.loads(args.report.read_text())
    reservation = json.loads(args.reservation.read_text())
    result = analyze(report, reservation)
    result["sourceReport"] = str(args.report)
    result["sourceReportSHA256"] = hashlib.sha256(args.report.read_bytes()).hexdigest()
    result["sourceRevision"] = report["source"]["revision"]
    args.output_json.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    args.output_markdown.write_text(markdown(result))


if __name__ == "__main__":
    main()
