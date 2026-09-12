#!/usr/bin/env python3
"""Validate version-1 longitudinal vocabulary diagnostic reports."""

from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any


class ValidationError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def validate_path(path: dict[str, Any], manifest: dict[str, Any], fixed: bool) -> None:
    require(path["questionCount"] <= 80, "question ceiling exceeded")
    require(path["assessableOccurrenceMass"] >= path["missedOccurrenceMass"] >= 0, "invalid occurrence mass")
    denominator = path["assessableOccurrenceMass"]
    expected_coverage = 1.0 if denominator == 0 else 1.0 - path["missedOccurrenceMass"] / denominator
    require(math.isclose(path["realizedProjectedCoverage"], expected_coverage, abs_tol=1e-12), "coverage mass mismatch")
    if fixed:
        require(path["requestedBudget"] == manifest["fixedBudget"], "fixed budget mismatch")
        reached = path["questionCount"] == manifest["fixedBudget"]
        require(path["reachedRequestedBudget"] == reached, "fixed budget reachability mismatch")
        if not reached:
            require(path.get("unreachableReason") in {"candidate-exhaustion", "question-limit"}, "missing unreachable reason")
    else:
        require(path.get("requestedBudget") is None, "natural path has a requested budget")

    bank_a, bank_b1, bank_b2 = path["bankA"], path["bankB1"], path["bankB2"]
    require(bank_a["kind"] == "productionA" and bank_a["sampleCount"] == 512, "invalid A bank")
    require(bank_b1["kind"] == "independentLatentB1", "invalid B1 bank")
    require(bank_b1["sampleCount"] == manifest["b1SampleCount"], "B1 sample mismatch")
    require(bank_b2["kind"] == "randomizedThetaAndLatentB2", "invalid B2 bank")
    require(bank_b2["sampleCount"] == manifest["b2SampleCount"], "B2 sample mismatch")
    require(math.isclose(bank_a["coverageLowerBound"], path["conservativeCoverageLowerBound"], abs_tol=1e-15), "A parity mismatch")
    require(math.isclose(path["b1MinusA"], bank_b1["coverageLowerBound"] - bank_a["coverageLowerBound"], abs_tol=1e-15), "B1-A mismatch")
    require(math.isclose(path["b2MinusA"], bank_b2["coverageLowerBound"] - bank_a["coverageLowerBound"], abs_tol=1e-15), "B2-A mismatch")
    require(math.isclose(path["b2MinusB1"], bank_b2["coverageLowerBound"] - bank_b1["coverageLowerBound"], abs_tol=1e-15), "B2-B1 mismatch")
    for bank in (bank_a, bank_b1, bank_b2):
        require(bank["thetaPositionFingerprint"] and bank["latentItemDrawFingerprint"], "missing bank fingerprint")


def validate_replay_mass(replay: dict[str, Any], assessable_mass: int) -> None:
    require(
        replay["assessableOccurrenceMass"] == assessable_mass,
        "replay assessable mass changed",
    )
    require(
        replay["assessableOccurrenceMass"] >= replay["missedOccurrenceMass"] >= 0,
        "invalid replay occurrence mass",
    )
    denominator = replay["assessableOccurrenceMass"]
    expected_coverage = 1.0 if denominator == 0 else 1.0 - replay["missedOccurrenceMass"] / denominator
    require(
        math.isclose(replay["realizedProjectedCoverage"], expected_coverage, abs_tol=1e-12),
        "replay coverage mass mismatch",
    )
    require(replay["selectedCount"] >= 0, "invalid replay selected count")
    require(replay["selectedFingerprint"], "missing replay selection fingerprint")


def validate_replay(replay: dict[str, Any], source: dict[str, Any]) -> None:
    require(replay["questionCount"] == source["questionCount"], "replay question count changed")
    validate_replay_mass(replay, source["assessableOccurrenceMass"])


def validate_compatibility(run: dict[str, Any]) -> None:
    diagnostic = run["warmCompatibility"]
    applicable = run["expectedWarmEligibility"]
    require(diagnostic["applicable"] == applicable, "compatibility applicability mismatch")
    require(diagnostic["validationQuestionOrdinals"] == [4, 8], "compatibility ordinals changed")
    count = diagnostic["nonExcludedValidationAnswerCount"]
    require(0 <= count <= 2, "invalid compatibility validation count")
    ratio = diagnostic.get("evidenceLogLikelihoodRatio")
    supported = diagnostic.get("supportsEightQuestionMinimum")
    if applicable:
        warm = diagnostic.get("warmEvidenceLogLikelihood")
        cold = diagnostic.get("coldEvidenceLogLikelihood")
        require(warm is not None and cold is not None, "applicable compatibility lacks likelihoods")
        if count == 2:
            require(ratio is not None, "supported compatibility lacks likelihood ratio")
            require(math.isclose(ratio, warm - cold, abs_tol=1e-12), "compatibility ratio mismatch")
            require(supported == (ratio >= 0), "compatibility threshold mismatch")
        else:
            require(ratio is None and supported is None, "unsupported validation count acquired decision")
    else:
        require(
            diagnostic.get("warmEvidenceLogLikelihood") is None
            and diagnostic.get("coldEvidenceLogLikelihood") is None
            and ratio is None
            and supported is None,
            "inapplicable compatibility acquired likelihood evidence",
        )

    expected_applied = applicable and supported is not True and run["warmNatural"]["questionCount"] < 20
    require(
        diagnostic["counterfactualMinimumApplied"] == expected_applied,
        "compatibility counterfactual application mismatch",
    )
    candidate = diagnostic["candidatePath"]
    validate_replay_mass(candidate, run["warmNatural"]["assessableOccurrenceMass"])
    if expected_applied:
        require(candidate["questionCount"] == 20, "compatibility path did not reach ordinary minimum")
        require(
            candidate["sourcePath"] == "accumulated-warm-compatibility-minimum-20",
            "compatibility counterfactual source mismatch",
        )
    else:
        require(
            candidate["answerPathFingerprint"] == run["warmNatural"]["answerPathFingerprint"],
            "non-applied compatibility path differs from warm natural",
        )
    cold_questions = run["coldNatural"]["questionCount"]
    expected_reduction = 0 if cold_questions == 0 else 1 - candidate["questionCount"] / cold_questions
    require(
        math.isclose(diagnostic["candidateQuestionReduction"], expected_reduction, abs_tol=1e-12),
        "compatibility question reduction mismatch",
    )
    require(
        math.isclose(
            diagnostic["candidateCoverageDifference"],
            candidate["realizedProjectedCoverage"] - run["coldNatural"]["realizedProjectedCoverage"],
            abs_tol=1e-12,
        ),
        "compatibility coverage difference mismatch",
    )


def production_eligible(prior: dict[str, Any] | None, evaluation_time: float) -> bool:
    if prior is None:
        return False
    return (
        prior["languageCode"] == "en"
        and prior["algorithmVersion"] == 3
        and prior["completedSessionCount"] >= 2
        and prior["verifiedEvidenceCount"] >= 40
        and prior["lastUpdatedAt"] <= evaluation_time
        and evaluation_time - prior["lastUpdatedAt"] <= 180 * 24 * 60 * 60
    )


def validate_run(run: dict[str, Any], manifest: dict[str, Any], report_schema: int) -> None:
    scenario = run["scenario"]
    completed_count = 0
    verified_count = 0
    for event in run["historyEvents"]:
        if event["disposition"] == "completed":
            require(event.get("completedAt") is not None, "completed history lacks completion time")
            completed_count += 1
            verified_count += event["verifiedEvidenceCount"]
            require(event.get("initialWriteSucceeded") is True or event.get("retryWriteSucceeded") is True, "completed session was not stored")
            require(event.get("duplicateWriteSucceeded") is True, "idempotent duplicate did not succeed")
            require(event.get("storedPosteriorMatchesCompletedAssessment") is True, "stored posterior differs from completion")
        else:
            require(event["disposition"] == "abandoned-no-contribution", "unknown history disposition")
            require(event.get("initialWriteSucceeded") is None, "abandoned history wrote a contribution")
            require(event.get("completedAt") is None, "abandoned history has a completion time")
            require(event["questionCount"] < event["requiredMinimumQuestionCount"], "abandoned history was actually complete")
            require(event.get("stopReason") is None, "abandoned history acquired a completion stop")
        require(event["storedSessionCountAfterEvent"] == completed_count, "session count is not idempotent")
        require(event["storedVerifiedCountAfterEvent"] == verified_count, "verified evidence count mismatch")

    prior = run.get("storedPrior")
    if scenario == "reset-before-evaluation":
        require(prior is None, "reset scenario retained a prior")
    else:
        require(prior is not None, "completed histories did not reopen")
        require(prior["completedSessionCount"] == completed_count, "final session count mismatch")
        require(prior["verifiedEvidenceCount"] == verified_count, "final verified count mismatch")
        last_completed = next(event for event in reversed(run["historyEvents"]) if event["disposition"] == "completed")
        require(prior["posteriorFingerprint"] == last_completed["storedPosteriorFingerprintAfterEvent"], "store did not retain latest reopened posterior")

    expected = production_eligible(prior, 2_000_000_000)
    require(run["expectedWarmEligibility"] == expected, "expected eligibility mismatch")
    require(run["coldNatural"]["usedEligiblePrior"] is False, "cold path used a prior")
    require(run["coldFixedBudget"]["usedEligiblePrior"] is False, "cold fixed path used a prior")
    require(run["warmNatural"]["usedEligiblePrior"] == expected, "warm natural eligibility mismatch")
    require(run["warmFixedBudget"]["usedEligiblePrior"] == expected, "warm fixed eligibility mismatch")
    if expected:
        required_minimum = run["warmNatural"]["requiredMinimumQuestionCount"]
        require(required_minimum in (8, 20), "eligible warm path has an invalid conditional minimum")
        require(run["warmNatural"]["questionCount"] >= required_minimum, "warm path stopped before its conditional minimum")
    else:
        parity_fields = (
            "questionCount", "requiredMinimumQuestionCount", "stopReason",
            "estimatedTheta", "thetaLowerBound", "thetaUpperBound", "brierScore",
            "expectedCalibrationError", "selectedCount", "selectedFingerprint",
            "answerPathFingerprint", "posteriorFingerprint", "assessableOccurrenceMass",
            "missedOccurrenceMass", "realizedProjectedCoverage", "conservativeCoverageLowerBound",
        )
        require(
            all(run["coldNatural"].get(field) == run["warmNatural"].get(field) for field in parity_fields),
            "ineligible warm natural path differs from cold",
        )
        require(
            all(run["coldFixedBudget"].get(field) == run["warmFixedBudget"].get(field) for field in parity_fields),
            "ineligible warm fixed path differs from cold",
        )

    for key, fixed in (
        ("coldNatural", False), ("warmNatural", False),
        ("coldFixedBudget", True), ("warmFixedBudget", True),
    ):
        validate_path(run[key], manifest, fixed)
    require(run["evaluationTruthFingerprint"], "missing evaluation truth fingerprint")
    require(run["evaluationPotentialResponseFingerprint"], "missing potential-response fingerprint")
    require(run["coldPathUnderWarmPrior"]["answerPathFingerprint"] == run["coldNatural"]["answerPathFingerprint"], "cold replay path changed evidence")
    require(run["warmPathUnderColdPrior"]["answerPathFingerprint"] == run["warmNatural"]["answerPathFingerprint"], "warm replay path changed evidence")
    if report_schema >= 2:
        replay_pairs = (
            ("coldPathUnderWarmPrior", "coldNatural"),
            ("warmPathUnderColdPrior", "warmNatural"),
            ("coldFixedPathUnderWarmPrior", "coldFixedBudget"),
            ("warmFixedPathUnderColdPrior", "warmFixedBudget"),
        )
        for replay_key, source_key in replay_pairs:
            replay = run[replay_key]
            source = run[source_key]
            require(
                replay["answerPathFingerprint"] == source["answerPathFingerprint"],
                f"{replay_key} changed source evidence",
            )
            validate_replay(replay, source)
    if report_schema >= 3:
        validate_compatibility(run)

    if scenario == "failed-write-retry":
        first = next(event for event in run["historyEvents"] if event["disposition"] == "completed")
        require(first["initialWriteSucceeded"] is False and first["retryWriteSucceeded"] is True, "failed-write retry not exercised")
    if scenario == "abandoned-session":
        require(any(event["disposition"] == "abandoned-no-contribution" for event in run["historyEvents"]), "abandoned session missing")


def validate_report(report: dict[str, Any]) -> None:
    report_schema = report.get("schemaVersion")
    require(report_schema in (1, 2, 3), "unsupported report schema")
    manifest = report["manifest"]
    require(manifest["schemaVersion"] == 1, "unsupported manifest schema")
    require(manifest["dataRole"] == "diagnostic-development", "confirmation/holdout role forbidden")
    require("personal-vocabulary.sqlite3" not in json.dumps(report), "user database path leaked into report")
    runs = report["runs"]
    ids = [run["runID"] for run in runs]
    require(len(ids) == len(set(ids)), "duplicate run ID")
    require({run["scenario"] for run in runs} == set(manifest["scenarios"]), "scenario support mismatch")
    for run in runs:
        validate_run(run, manifest, report_schema)
    eligible = sum(run["expectedWarmEligibility"] for run in runs)
    require(report["support"]["runs"] == len(runs), "run support mismatch")
    require(report["support"]["eligibleWarmRuns"] == eligible, "eligible support mismatch")
    require(report["support"]["ineligibleWarmRuns"] == len(runs) - eligible, "ineligible support mismatch")
    require(report["support"]["naturalWarmPriorUsed"] == eligible, "warm-use support mismatch")


def self_test(path: Path) -> None:
    report = json.loads(path.read_text())
    validate_report(report)
    mutations = []
    broken_count = copy.deepcopy(report)
    broken_count["runs"][0]["historyEvents"][0]["storedSessionCountAfterEvent"] += 1
    mutations.append(broken_count)
    broken_eligibility = copy.deepcopy(report)
    broken_eligibility["runs"][0]["warmNatural"]["usedEligiblePrior"] = not broken_eligibility["runs"][0]["warmNatural"]["usedEligiblePrior"]
    mutations.append(broken_eligibility)
    broken_mass = copy.deepcopy(report)
    broken_mass["runs"][0]["coldNatural"]["missedOccurrenceMass"] += 1
    mutations.append(broken_mass)
    broken_replay = copy.deepcopy(report)
    broken_replay["runs"][0]["coldPathUnderWarmPrior"]["answerPathFingerprint"] = "broken"
    mutations.append(broken_replay)
    if report.get("schemaVersion") >= 2:
        broken_replay_mass = copy.deepcopy(report)
        broken_replay_mass["runs"][0]["coldFixedPathUnderWarmPrior"]["missedOccurrenceMass"] += 1
        mutations.append(broken_replay_mass)
    if report.get("schemaVersion") >= 3:
        broken_compatibility = copy.deepcopy(report)
        broken_compatibility["runs"][0]["warmCompatibility"]["candidateCoverageDifference"] += 0.1
        mutations.append(broken_compatibility)
    for mutation in mutations:
        try:
            validate_report(mutation)
        except ValidationError:
            continue
        raise AssertionError("invalid longitudinal report unexpectedly passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test(args.report)
        print("vocabulary longitudinal validator self-test passed")
    else:
        validate_report(json.loads(args.report.read_text()))
        print("vocabulary longitudinal report valid")


if __name__ == "__main__":
    main()
