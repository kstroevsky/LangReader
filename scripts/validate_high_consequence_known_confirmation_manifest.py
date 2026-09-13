#!/usr/bin/env python3
"""Validate the frozen high-consequence confirmation feasibility reservation."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path


class ValidationError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ValidationError(message)


def validate(manifest, root):
    require(manifest.get("schemaVersion") == 1, "unsupported schema")
    require(manifest.get("dataRole") == "diagnostic-development-feasibility", "invalid data role")
    status = manifest.get("reservationStatus")
    require(
        status in {"frozen-not-executed", "consumed-candidate-rejected"},
        "invalid reservation status",
    )
    if status == "frozen-not-executed":
        require(manifest.get("outcomes") is None, "unexecuted reservation contains outcomes")
        require(manifest.get("consumedAtRevision") is None, "unexecuted reservation is marked consumed")
    else:
        outcomes = manifest.get("outcomes")
        revision = manifest.get("consumedAtRevision")
        require(isinstance(outcomes, dict), "consumed reservation lacks outcomes")
        require(outcomes["executionSourceRevision"] == revision, "execution revision mismatch")
        for path_key, hash_key in (
            ("semanticReport", "semanticReportSHA256"),
            ("analysis", "analysisSHA256"),
        ):
            path = root / outcomes[path_key]
            require(path.is_file(), f"consumed {path_key} missing")
            require(
                hashlib.sha256(path.read_bytes()).hexdigest() == outcomes[hash_key],
                f"consumed {path_key} checksum mismatch",
            )
        require(outcomes["retainedRuns"] == 1024 and outcomes["eligibleRuns"] == 1013, "result support changed")
        require(outcomes["productionMaterialTailCount"] == 40, "baseline tail count changed")
        require(outcomes["independentArmMaterialTailCount"] == 32, "candidate tail count changed")
        require(outcomes["candidatePass"] is False, "rejected candidate marked passing")
        require(outcomes["decision"] == "reject-feasibility-candidate", "decision changed")

    source = manifest["sourceMechanismEvidence"]
    source_path = root / source["analysis"]
    require(source_path.is_file(), "mechanism evidence missing")
    require(
        hashlib.sha256(source_path.read_bytes()).hexdigest() == source["analysisSHA256"],
        "mechanism evidence checksum mismatch",
    )

    candidate = manifest["candidate"]
    require(candidate["name"] == "high-consequence-known-double-confirmation-v1", "candidate changed")
    require(candidate["missMassBudget"] == "floor((1 - targetCoverage) * assessableOccurrenceMass)", "budget rule changed")
    require(candidate["posteriorAndThetaUpdated"] is False, "posterior update enabled")
    require(candidate["questionPathUpdated"] is False, "question path update enabled")
    require(candidate["maximumTotalQuestions"] == 80, "question ceiling changed")
    require(candidate["productionActivation"] is False, "production activation enabled")

    workload = manifest["workload"]
    require(len(workload["scenarios"]) == len(set(workload["scenarios"])) == 8, "scenario support changed")
    require(workload["learnersPerScenario"] == 128, "learner support changed")
    require(workload["plannedRows"] == 1024, "planned support changed")
    require(workload["retainEveryRow"] is True, "row retention is not mandatory")

    decision = manifest["decisionRule"]
    require(decision["materialCoverageDegradation"] == -0.02, "materiality boundary changed")
    require(decision["independentArmMaximumMaterialTailCount"] == 0, "tail gate changed")
    require(decision["independentArmMinimumMeanCoverageDifference"] == -0.005, "coverage gate changed")
    require(decision["independentArmMinimumMeanQuestionReduction"] == 0.5, "efficiency gate changed")
    require(decision["fullyCorrelatedArmIsNegativeControl"] is True, "correlated control removed")
    require(decision["noApprovedUXCostThreshold"] is True, "UX threshold was invented")
    require(decision["passingDoesNotAuthorizeProduction"] is True, "passing would activate production")
    require(all(manifest["requiredExternalEvidence"].values()), "external evidence requirement relaxed")
    require(all(manifest["forbiddenAccess"].values()), "access boundary relaxed")


def self_test(manifest, root):
    validate(manifest, root)
    mutations = []
    changed_budget = copy.deepcopy(manifest)
    changed_budget["candidate"]["missMassBudget"] = "tuned threshold"
    mutations.append(changed_budget)
    changed_gate = copy.deepcopy(manifest)
    changed_gate["decisionRule"]["independentArmMaximumMaterialTailCount"] = 1
    mutations.append(changed_gate)
    relaxed = copy.deepcopy(manifest)
    relaxed["forbiddenAccess"]["developmentConfirmation"] = False
    mutations.append(relaxed)
    invalid_status = copy.deepcopy(manifest)
    invalid_status["reservationStatus"] = "available-again"
    mutations.append(invalid_status)
    for mutation in mutations:
        try:
            validate(mutation, root)
        except ValidationError:
            continue
        raise AssertionError("invalid high-consequence confirmation manifest unexpectedly passed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    manifest = json.loads(args.manifest.read_text())
    if args.self_test:
        self_test(manifest, root)
        print("high-consequence known confirmation manifest self-test passed")
    else:
        validate(manifest, root)
        print("high-consequence known confirmation manifest valid")


if __name__ == "__main__":
    main()
