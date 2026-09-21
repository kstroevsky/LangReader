#!/usr/bin/env python3
"""Validate the version-1 synthetic causal-diagnostic artifact."""

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


def validate_path(path: dict[str, Any], target: float) -> None:
    items = path["items"]
    keys = [item["canonicalKey"] for item in items]
    require(len(keys) == len(set(keys)), "duplicate item key")
    questions = path["questions"]
    question_keys = [question["canonicalKey"] for question in questions]
    require(len(question_keys) == len(set(question_keys)), "duplicate question key")
    require(path["questionCount"] == len(questions), "question count mismatch")
    require(path["questionCount"] <= 80, "question ceiling exceeded")
    if path.get("requestedBudget") is not None:
        reached = path["questionCount"] == path["requestedBudget"]
        require(path["reachedRequestedBudget"] == reached, "fixed-budget reachability mismatch")
        if not reached:
            require(path.get("unreachableReason") in {"question-limit", "candidate-exhaustion"}, "missing unreachable-budget reason")

    selected = set(path["selectedKeys"])
    require(selected == {item["canonicalKey"] for item in items if item["isSelected"]}, "selection mismatch")
    require(not any(item["isExcluded"] and item["isSelected"] for item in items), "excluded item selected")

    denominator = sum(item["occurrenceCount"] for item in items if not item["isExcluded"])
    excluded = sum(item["occurrenceCount"] for item in items if item["isExcluded"])
    missed_items = [
        item for item in items
        if not item["isExcluded"] and not item["truthKnown"] and not item["isSelected"]
    ]
    missed = sum(item["occurrenceCount"] for item in missed_items)
    answered = sum(item["occurrenceCount"] for item in missed_items if item["responseState"] == "answered")
    unasked = sum(item["occurrenceCount"] for item in missed_items if item["responseState"] != "answered")
    skipped = sum(item["occurrenceCount"] for item in missed_items if item["responseState"] == "skipped")
    evidence: dict[str, int] = {}
    for item in missed_items:
        if item["responseState"] == "answered":
            label = item["evidence"] or "missing"
            evidence[label] = evidence.get(label, 0) + item["occurrenceCount"]
    forensic = path["forensics"]
    require(forensic["assessableOccurrenceMass"] == denominator, "denominator mismatch")
    require(forensic["excludedOccurrenceMass"] == excluded, "excluded mass mismatch")
    require(forensic["missedMass"] == missed, "missed mass mismatch")
    require(forensic["answeredMissedMass"] == answered, "answered missed mass mismatch")
    require(forensic["unaskedMissedMass"] == unasked, "unasked missed mass mismatch")
    require(forensic["skippedMissedMassWithinUnasked"] == skipped, "skipped missed mass mismatch")
    require(forensic["answeredEvidenceMass"] == evidence, "answered evidence partition mismatch")
    require(answered + unasked == missed, "missed mass does not conserve")
    require(sum(evidence.values()) == answered, "answered evidence does not conserve")
    coverage = 1.0 if denominator == 0 else 1.0 - missed / denominator
    require(math.isclose(forensic["realizedProjectedCoverage"], coverage, abs_tol=1e-12), "coverage mismatch")
    require(math.isclose(path["realizedProjectedCoverage"], coverage, abs_tol=1e-12), "path coverage mismatch")
    require(math.isclose(path["targetShortfall"], max(0.0, target - coverage), abs_tol=1e-12), "shortfall mismatch")
    require(forensic["claimEligible"] == (denominator > 0), "claim eligibility mismatch")

    banks = path["bankEvaluations"]
    require(banks, "missing bank evaluations")
    for bank in banks:
        result = bank["result"]
        require(result["sampleCount"] > 0, "invalid bank sample count")
        require(sum(entry["sampleCount"] for entry in result["thetaPositionHistogram"]) == result["sampleCount"], "theta mass mismatch")
        require(math.isfinite(result["coverageLowerBound"]), "non-finite bank lower bound")
        require(0 <= result["coverageLowerBound"] <= 1, "bank lower bound outside 0...1")
        require(0 <= result["targetMissProbability"] <= 1, "bank miss probability outside 0...1")
        if result["kind"] == "productionA":
            require(result["sampleCount"] == 512, "A must use 512 samples")
        if result["kind"] == "independentLatentB1":
            require(result["sampleCount"] % 512 == 0, "B1 must preserve 512-position mass")

    for role in {bank["deckRole"] for bank in banks}:
        a = next(bank for bank in banks if bank["deckRole"] == role and bank["result"]["kind"] == "productionA")
        a_mass = {entry["thetaGridIndex"]: entry["sampleCount"] for entry in a["result"]["thetaPositionHistogram"]}
        for bank in banks:
            result = bank["result"]
            if bank["deckRole"] != role or result["kind"] != "independentLatentB1":
                continue
            factor = result["sampleCount"] // 512
            b1_mass = {entry["thetaGridIndex"]: entry["sampleCount"] for entry in result["thetaPositionHistogram"]}
            require(b1_mass == {key: count * factor for key, count in a_mass.items()}, "B1 theta mass differs from A")


def validate_report(report: dict[str, Any]) -> None:
    require(report.get("schemaVersion") == 1, "unsupported report schema")
    manifest = report["manifest"]
    require(manifest["schemaVersion"] == 1, "unsupported manifest schema")
    require(manifest["dataRole"] == "diagnostic-development", "confirmation/holdout role is forbidden")
    target = manifest["targetCoverage"]
    require(math.isfinite(target) and 0 <= target <= 1, "invalid target")
    runs = report["runs"]
    run_ids = [run["runID"] for run in runs]
    require(len(run_ids) == len(set(run_ids)), "duplicate run ID")
    require(report["retainedRunCounts"]["allRuns"] == len(runs), "retained run count mismatch")
    require(report["retainedRunCounts"]["detailedRuns"] == len(runs), "not all detailed runs retained")
    for run in runs:
        require(run["truthFingerprint"], "missing truth fingerprint")
        require(run["potentialResponseFingerprint"], "missing response fingerprint")
        validate_path(run["natural"], target)
        validate_path(run["fixedBudget"], target)
        natural_static = {
            item["canonicalKey"]: (
                item["truthKnown"], item["occurrenceCount"], item["actualSyntheticDifficulty"],
                item["potentialResponseEvidence"], item["potentialResponseDraw"],
            )
            for item in run["natural"]["items"]
        }
        fixed_static = {
            item["canonicalKey"]: (
                item["truthKnown"], item["occurrenceCount"], item["actualSyntheticDifficulty"],
                item["potentialResponseEvidence"], item["potentialResponseDraw"],
            )
            for item in run["fixedBudget"]["items"]
        }
        require(natural_static == fixed_static, "truth/potential responses changed across paths")
    replay_ids = [control["controlID"] for control in report["replayControls"]]
    require(len(replay_ids) == len(set(replay_ids)), "duplicate replay control ID")
    require(all(control["evidencePathFingerprint"] for control in report["replayControls"]), "missing replay fingerprint")


def self_test(fixture_path: Path) -> None:
    report = json.loads(fixture_path.read_text())
    validate_report(report)
    mutations = []
    broken_denominator = copy.deepcopy(report)
    broken_denominator["runs"][0]["natural"]["forensics"]["assessableOccurrenceMass"] += 1
    mutations.append(broken_denominator)
    duplicate_run = copy.deepcopy(report)
    duplicate_run["runs"].append(copy.deepcopy(duplicate_run["runs"][0]))
    duplicate_run["retainedRunCounts"]["allRuns"] += 1
    duplicate_run["retainedRunCounts"]["detailedRuns"] += 1
    mutations.append(duplicate_run)
    broken_fingerprint = copy.deepcopy(report)
    broken_fingerprint["runs"][0]["truthFingerprint"] = ""
    mutations.append(broken_fingerprint)
    broken_b1 = copy.deepcopy(report)
    b1 = next(
        bank for bank in broken_b1["runs"][0]["natural"]["bankEvaluations"]
        if bank["result"]["kind"] == "independentLatentB1"
    )
    b1["result"]["thetaPositionHistogram"][0]["sampleCount"] += 1
    mutations.append(broken_b1)
    for mutation in mutations:
        try:
            validate_report(mutation)
        except ValidationError:
            continue
        raise AssertionError("invalid causal report unexpectedly passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("report", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        if args.report is None:
            parser.error("report path is required with --self-test")
        self_test(args.report)
        print("vocabulary causal diagnostic validator self-test passed")
        return
    if args.report is None:
        parser.error("report path is required")
    validate_report(json.loads(args.report.read_text()))
    print("vocabulary causal diagnostic report valid")


if __name__ == "__main__":
    main()
