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
    status = manifest.get("reservationStatus")
    require(status in {"frozen-not-executed", "consumed"}, "invalid reservation status")
    if status == "frozen-not-executed":
        require(manifest.get("outcomes") is None, "unexecuted reservation contains outcomes")
        require(manifest.get("consumedAtRevision") is None, "unexecuted reservation is marked consumed")
    else:
        outcomes = manifest.get("outcomes")
        revision = manifest.get("consumedAtRevision")
        require(isinstance(outcomes, dict), "consumed reservation lacks outcomes")
        require(isinstance(revision, str) and len(revision) == 40, "invalid consumption revision")
        require(outcomes["executionSourceRevision"] == revision, "execution revision mismatch")
        outcome_report = root / outcomes["semanticReport"]
        require(outcome_report.is_file(), "consumed semantic report is missing")
        require(
            hashlib.sha256(outcome_report.read_bytes()).hexdigest()
            == outcomes["semanticReportSHA256"],
            "consumed semantic report checksum mismatch",
        )
        require(outcomes["retainedRuns"] == 1024, "consumed run support mismatch")
        require(outcomes["candidatePass"] is False, "rejected candidate marked passing")
        require(
            outcomes["decision"] == "reject-candidate-retain-production",
            "consumed decision mismatch",
        )

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
    invalid_status = copy.deepcopy(manifest)
    invalid_status["reservationStatus"] = "available-again"
    mutations.append(invalid_status)
    changed_threshold = copy.deepcopy(manifest)
    changed_threshold["candidateCompatibilitySignal"]["supportThreshold"] = -0.1
    mutations.append(changed_threshold)
    relaxed_access = copy.deepcopy(manifest)
    relaxed_access["forbiddenAccess"]["developmentConfirmation"] = False
    mutations.append(relaxed_access)
    if manifest["reservationStatus"] == "consumed":
        changed_outcome = copy.deepcopy(manifest)
        changed_outcome["outcomes"]["semanticReportSHA256"] = "0" * 64
        mutations.append(changed_outcome)
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
