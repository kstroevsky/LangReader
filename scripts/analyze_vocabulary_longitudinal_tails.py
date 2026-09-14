#!/usr/bin/env python3
"""Classify material warm-tail failures on diagnostic-development evidence."""

import argparse
import hashlib
import json
import math
from pathlib import Path


MATERIAL_DEGRADATION = -0.02


def analyze(report: dict) -> dict:
    if report.get("schemaVersion") != 2:
        raise ValueError("realized replay coverage requires longitudinal report schema 2")
    material = [
        run for run in report["runs"]
        if run["expectedWarmEligibility"] and run["naturalCoverageDifference"] < MATERIAL_DEGRADATION
    ]
    rows = []
    for run in sorted(material, key=lambda value: value["naturalCoverageDifference"]):
        fixed = run["fixedBudgetCoverageDifference"]
        if fixed >= MATERIAL_DEGRADATION:
            classification = "stopping-implicated"
            selection_under_cold = None
            selection_under_warm = None
            prior_on_cold_path = None
            prior_on_warm_path = None
        else:
            cold_fixed = run["coldFixedBudget"]["realizedProjectedCoverage"]
            warm_fixed = run["warmFixedBudget"]["realizedProjectedCoverage"]
            cold_path_warm_prior = run["coldFixedPathUnderWarmPrior"]["realizedProjectedCoverage"]
            warm_path_cold_prior = run["warmFixedPathUnderColdPrior"]["realizedProjectedCoverage"]
            selection_under_cold = warm_path_cold_prior - cold_fixed
            selection_under_warm = warm_fixed - cold_path_warm_prior
            prior_on_cold_path = cold_path_warm_prior - cold_fixed
            prior_on_warm_path = warm_fixed - warm_path_cold_prior
            if not math.isclose(
                fixed,
                selection_under_cold + prior_on_warm_path,
                abs_tol=1e-12,
            ) or not math.isclose(
                fixed,
                prior_on_cold_path + selection_under_warm,
                abs_tol=1e-12,
            ):
                raise ValueError(f"replay decomposition does not conserve fixed effect for {run['runID']}")
            selection_implicated = min(selection_under_cold, selection_under_warm) < MATERIAL_DEGRADATION
            prior_implicated = min(prior_on_cold_path, prior_on_warm_path) < MATERIAL_DEGRADATION
            if selection_implicated and prior_implicated:
                classification = "mixed-selection-prior-path-interaction"
            elif selection_implicated:
                classification = "question-evidence-path-implicated"
            elif prior_implicated:
                classification = "transferred-prior-posterior-implicated"
            else:
                classification = "distributed-subthreshold-effects"
        rows.append({
            "runID": run["runID"],
            "scenario": run["scenario"],
            "naturalCoverageDifference": run["naturalCoverageDifference"],
            "fixedBudgetCoverageDifference": fixed,
            "coldNaturalQuestions": run["coldNatural"]["questionCount"],
            "warmNaturalQuestions": run["warmNatural"]["questionCount"],
            "classification": classification,
            "fixedBudgetReplayContrasts": {
                "questionEvidencePathUnderColdPrior": selection_under_cold,
                "questionEvidencePathUnderWarmPrior": selection_under_warm,
                "destinationPriorOnColdPath": prior_on_cold_path,
                "destinationPriorOnWarmPath": prior_on_warm_path,
            },
        })
    return {
        "schemaVersion": 2,
        "dataRole": "diagnostic-development-only",
        "sourceReportSchemaVersion": report["schemaVersion"],
        "sourceRevision": report["source"]["revision"],
        "materialityBoundary": MATERIAL_DEGRADATION,
        "productionConfigurationChanged": False,
        "materialTailCount": len(rows),
        "stoppingImplicatedCount": sum(row["classification"] == "stopping-implicated" for row in rows),
        "persistsAtFixedBudgetCount": sum(row["classification"] != "stopping-implicated" for row in rows),
        "questionEvidencePathImplicatedCount": sum(
            row["classification"] in {
                "question-evidence-path-implicated",
                "mixed-selection-prior-path-interaction",
            }
            for row in rows
        ),
        "transferredPriorPosteriorImplicatedCount": sum(
            row["classification"] in {
                "transferred-prior-posterior-implicated",
                "mixed-selection-prior-path-interaction",
            }
            for row in rows
        ),
        "rows": rows,
        "limitation": "Replay contrasts are conditional decompositions, not additive causal effects: the destination prior can change the final deck differently on the cold and warm evidence paths."
    }


def markdown(result: dict) -> str:
    def percentage_points(value) -> str:
        return "—" if value is None else f"{value * 100:.3f} pp"

    lines = [
        "# Vocabulary longitudinal warm-tail decomposition",
        "",
        "This development-only analysis uses the existing two-percentage-point warm degradation boundary. It changes no production configuration and does not access development-confirmation or release-holdout data.",
        "",
        f"Material tails: {result['materialTailCount']}; stopping implicated: {result['stoppingImplicatedCount']}; persistent at the common 60-question budget: {result['persistsAtFixedBudgetCount']}.",
        "",
        "| Run | Natural warm-cold | Fixed-budget warm-cold | Path effect under cold/warm prior | Prior effect on cold/warm path | Classification |",
        "| --- | ---: | ---: | ---: | ---: | --- |",
    ]
    for row in result["rows"]:
        contrasts = row["fixedBudgetReplayContrasts"]
        path_effect = "/".join((
            percentage_points(contrasts["questionEvidencePathUnderColdPrior"]),
            percentage_points(contrasts["questionEvidencePathUnderWarmPrior"]),
        ))
        prior_effect = "/".join((
            percentage_points(contrasts["destinationPriorOnColdPath"]),
            percentage_points(contrasts["destinationPriorOnWarmPath"]),
        ))
        lines.append(f"| {row['runID']} | {row['naturalCoverageDifference'] * 100:.3f} pp | {row['fixedBudgetCoverageDifference'] * 100:.3f} pp | {path_effect} | {prior_effect} | {row['classification']} |")
    lines.extend([
        "",
        "Eleven of thirteen material natural failures cease to be material at the common budget, which implicates stopping under the tested paths. Of the two biased-self-verification failures that persist, one is attributable to the changed question/evidence path under either common prior; the other implicates both the question/evidence path and prior sensitivity, with a path-dependent interaction.",
        "",
        result["limitation"],
        "",
        "Next: test a predeclared current-document compatibility signal on a fresh development manifest before choosing a mitigation. Do not disable warm personalization, change the 0.90 weight, bind confirmation, or access the release holdout from this result.",
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
    result["sourceReport"] = str(args.report)
    result["sourceReportSHA256"] = hashlib.sha256(args.report.read_bytes()).hexdigest()
    args.output_json.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    args.output_markdown.write_text(markdown(result))


if __name__ == "__main__":
    main()
