#!/usr/bin/env python3
"""Validate the frozen warm compatibility development reservation."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path


class ValidationError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def validate(manifest: dict, root: Path) -> None:
    require(manifest.get("schemaVersion") == 1, "unsupported schema")
    require(manifest.get("dataRole") == "diagnostic-development", "non-development role forbidden")
    require(manifest.get("reservationStatus") == "frozen-not-executed", "reservation is not sealed")
    require(manifest.get("outcomes") is None, "reservation already contains outcomes")
    require(manifest.get("consumedAtRevision") is None, "reservation already consumed")

    source = manifest["sourceEvidence"]
    report_path = root / source["report"]
    require(report_path.is_file(), "source report is missing")
    require(
        hashlib.sha256(report_path.read_bytes()).hexdigest() == source["reportSHA256"],
        "source report checksum mismatch",
    )

    baseline = manifest["productionBaseline"]
    require(baseline["algorithmVersion"] == 3, "algorithm version changed")
    require(baseline["warmPriorWeight"] == 0.9, "warm weight changed")
    require(baseline["warmValidationOrdinals"] == [4, 8], "validation ordinals changed")
    require(
        baseline["ordinaryMinimumQuestionCount"] == 20
        and baseline["eligibleWarmMinimumQuestionCount"] == 8,
        "question minima changed",
    )

    signal = manifest["candidateCompatibilitySignal"]
    require(signal["observationModelVersion"] == "categorical-evidence-v1", "observation model changed")
    require(signal["evidenceReliabilityScale"] == 1.0, "evidence reliability changed")
    require(signal["minimumNonExcludedValidationAnswers"] == 2, "validation support changed")
    require(signal["supportThreshold"] == 0.0, "compatibility threshold changed")

    workload = manifest["workload"]
    require(len(workload["scenarios"]) == len(set(workload["scenarios"])) == 8, "scenario support changed")
    require(workload["learnersPerScenario"] == 128, "learner support changed")
    require(
        workload["plannedEligibleRuns"]
        == len(workload["scenarios"]) * workload["learnersPerScenario"]
        == 1024,
        "planned run support mismatch",
    )
    require(workload["retainEveryRow"] is True, "row retention is not mandatory")

    precision = manifest["precisionPlan"]
    for count, key in (
        (workload["plannedEligibleRuns"], "zeroEventOneSided95UpperBoundOverall"),
        (workload["learnersPerScenario"], "zeroEventOneSided95UpperBoundPerScenario"),
    ):
        expected = 1 - math.pow(0.05, 1 / count)
        require(math.isclose(precision[key], expected, abs_tol=1e-15), f"invalid precision bound {key}")

    decision = manifest["decisionRule"]
    require(decision["materialCoverageDegradation"] == -0.02, "materiality boundary changed")
    require(decision["maximumMaterialTailCount"] == 0, "tail acceptance changed")
    require(decision["minimumMeanWarmMinusColdCoverage"] == -0.005, "mean safety bound changed")
    require(decision["minimumMeanQuestionReduction"] == 0.5, "efficiency bound changed")
    require(decision["noThresholdTuningAfterOutcome"] is True, "outcome tuning is not forbidden")
    require(all(manifest["forbiddenAccess"].values()), "an access boundary was relaxed")


def self_test(manifest: dict, root: Path) -> None:
    validate(manifest, root)
    mutations = []
    with_outcome = copy.deepcopy(manifest)
    with_outcome["outcomes"] = {"peeked": True}
    mutations.append(with_outcome)
    changed_threshold = copy.deepcopy(manifest)
    changed_threshold["candidateCompatibilitySignal"]["supportThreshold"] = -0.1
    mutations.append(changed_threshold)
    relaxed_access = copy.deepcopy(manifest)
    relaxed_access["forbiddenAccess"]["developmentConfirmation"] = False
    mutations.append(relaxed_access)
    for mutation in mutations:
        try:
            validate(mutation, root)
        except ValidationError:
            continue
        raise AssertionError("invalid compatibility manifest unexpectedly passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    manifest = json.loads(args.manifest.read_text())
    if args.self_test:
        self_test(manifest, root)
        print("vocabulary longitudinal compatibility manifest self-test passed")
    else:
        validate(manifest, root)
        print("vocabulary longitudinal compatibility manifest valid")


if __name__ == "__main__":
    main()
