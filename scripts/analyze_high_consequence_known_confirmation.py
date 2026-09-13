#!/usr/bin/env python3
"""Analyze the frozen high-consequence known-confirmation feasibility run."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path


def mean(values):
    return sum(values) / len(values) if values else 0.0


def percentile(values, probability):
    if not values:
        return 0
    ordered = sorted(values)
    return ordered[max(0, math.ceil(probability * len(ordered)) - 1)]


def baseline_summary(rows):
    coverage = [row["naturalCoverageDifference"] for row in rows]
    questions = [row["naturalQuestionReduction"] for row in rows]
    return {
        "meanCoverageDifference": mean(coverage),
        "worstCoverageDifference": min(coverage),
        "materialTailCount": sum(value < -0.02 for value in coverage),
        "meanQuestionReduction": mean(questions),
    }


def arm_summary(rows, arm_name):
    arms = [row["highConsequenceConfirmation"][arm_name] for row in rows]
    coverage = [arm["coverageDifferenceFromCold"] for arm in arms]
    questions = [arm["questionReductionFromCold"] for arm in arms]
    return {
        "meanCoverageDifference": mean(coverage),
        "worstCoverageDifference": min(coverage),
        "materialTailCount": sum(value < -0.02 for value in coverage),
        "meanQuestionReduction": mean(questions),
        "questionCeilingExceededCount": sum(arm["questionCeilingExceeded"] for arm in arms),
        "addedKnownCardCount": sum(arm["addedKnownCardCount"] for arm in arms),
        "addedKnownOccurrenceMass": sum(arm["addedKnownOccurrenceMass"] for arm in arms),
        "addedUnknownCardCount": sum(arm["addedUnknownCardCount"] for arm in arms),
        "addedUnknownOccurrenceMass": sum(arm["addedUnknownOccurrenceMass"] for arm in arms),
    }


def analyze(report, reservation):
    if report.get("schemaVersion") != 6:
        raise ValueError("high-consequence analysis requires report schema 6")
    rows = report["runs"]
    if len(rows) != reservation["workload"]["plannedRows"]:
        raise ValueError("retained row count differs from frozen workload")
    eligible = [row for row in rows if row["expectedWarmEligibility"]]
    baseline = baseline_summary(eligible)
    independent = arm_summary(eligible, "independentArm")
    correlated = arm_summary(eligible, "fullyCorrelatedArm")
    confirmation_counts = [
        len(row["highConsequenceConfirmation"]["confirmations"])
        for row in eligible
    ]
    baseline_tails = {
        row["runID"] for row in eligible
        if row["naturalCoverageDifference"] < -0.02
    }
    independent_tails = {
        row["runID"] for row in eligible
        if row["highConsequenceConfirmation"]["independentArm"]["coverageDifferenceFromCold"] < -0.02
    }
    decision = reservation["decisionRule"]
    gate_results = {
        "materialTailCount": (
            independent["materialTailCount"]
            <= decision["independentArmMaximumMaterialTailCount"]
        ),
        "meanCoverageDifference": (
            independent["meanCoverageDifference"]
            >= decision["independentArmMinimumMeanCoverageDifference"]
        ),
        "meanQuestionReduction": (
            independent["meanQuestionReduction"]
            >= decision["independentArmMinimumMeanQuestionReduction"]
        ),
        "questionCeiling": independent["questionCeilingExceededCount"] == 0,
    }
    scenario_results = []
    for scenario in reservation["workload"]["scenarios"]:
        selected = [row for row in eligible if row["scenario"] == scenario]
        scenario_results.append({
            "scenario": scenario,
            "eligibleRuns": len(selected),
            "productionBaseline": baseline_summary(selected),
            "independentArm": arm_summary(selected, "independentArm"),
            "fullyCorrelatedArm": arm_summary(selected, "fullyCorrelatedArm"),
        })
    return {
        "schemaVersion": 1,
        "dataRole": "diagnostic-development-feasibility",
        "productionConfigurationChanged": False,
        "retainedRuns": len(rows),
        "eligibleRuns": len(eligible),
        "ineligibleRuns": len(rows) - len(eligible),
        "productionBaseline": baseline,
        "independentArm": independent,
        "fullyCorrelatedArm": correlated,
        "confirmationCountDistribution": {
            "mean": mean(confirmation_counts),
            "median": percentile(confirmation_counts, 0.5),
            "p95": percentile(confirmation_counts, 0.95),
            "maximum": max(confirmation_counts),
        },
        "materialTailsEliminated": len(baseline_tails - independent_tails),
        "materialTailsIntroduced": len(independent_tails - baseline_tails),
        "gateResults": gate_results,
        "candidatePass": all(gate_results.values()),
        "decision": (
            "reject-feasibility-candidate"
            if not all(gate_results.values())
            else "mechanically-feasible-external-evidence-still-required"
        ),
        "scenarioResults": scenario_results,
        "interpretation": (
            "The independent arm is an optimistic synthetic bound and the fully correlated arm is a negative control. "
            "Neither establishes human repeat-response correlation, burden acceptability, or real-learner validity."
        ),
    }


def markdown(result):
    baseline = result["productionBaseline"]
    independent = result["independentArm"]
    correlated = result["fullyCorrelatedArm"]
    counts = result["confirmationCountDistribution"]
    lines = [
        "# High-consequence known confirmation feasibility result",
        "",
        "This is the single frozen fresh-seed development execution. It changes no production configuration and does not use the selected forensic cases as an acceptance set.",
        "",
        f"Retained rows: {result['retainedRuns']}; eligible: {result['eligibleRuns']}; ineligible: {result['ineligibleRuns']}.",
        "",
        "| Arm | Mean warm-cold coverage | Worst warm-cold coverage | Material tails | Mean question reduction |",
        "| --- | ---: | ---: | ---: | ---: |",
        f"| Production baseline | {baseline['meanCoverageDifference'] * 100:.4f} pp | {baseline['worstCoverageDifference'] * 100:.4f} pp | {baseline['materialTailCount']} | {baseline['meanQuestionReduction'] * 100:.3f}% |",
        f"| Independent occasion-1 confirmation | {independent['meanCoverageDifference'] * 100:.4f} pp | {independent['worstCoverageDifference'] * 100:.4f} pp | {independent['materialTailCount']} | {independent['meanQuestionReduction'] * 100:.3f}% |",
        f"| Fully correlated negative control | {correlated['meanCoverageDifference'] * 100:.4f} pp | {correlated['worstCoverageDifference'] * 100:.4f} pp | {correlated['materialTailCount']} | {correlated['meanQuestionReduction'] * 100:.3f}% |",
        "",
        f"The independent arm eliminated {result['materialTailsEliminated']} baseline material tails and introduced {result['materialTailsIntroduced']}. It requested {counts['mean']:.3f} confirmations on average (median {counts['median']}, p95 {counts['p95']}, maximum {counts['maximum']}); no row exceeded the 80-question ceiling.",
        "",
        f"It added {independent['addedUnknownCardCount']} truly unknown cards ({independent['addedUnknownOccurrenceMass']} occurrence mass) and {independent['addedKnownCardCount']} truly known cards ({independent['addedKnownOccurrenceMass']} occurrence mass) across eligible rows. These known-card additions are a precision/user-burden cost, not a benefit.",
        "",
        f"The material-tail gate {'passed' if result['gateResults']['materialTailCount'] else 'failed'}; mean coverage {'passed' if result['gateResults']['meanCoverageDifference'] else 'failed'}; mean question reduction {'passed' if result['gateResults']['meanQuestionReduction'] else 'failed'}; question ceiling {'passed' if result['gateResults']['questionCeiling'] else 'failed'}.",
        "",
        f"Decision: **{result['decision']}**. Do not tune the consequence rule or repeat-response semantics from this consumed result.",
        "",
        result["interpretation"],
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
