#!/usr/bin/env python3
"""Validate the frozen selected-case warm question-path forensic manifest."""

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


def selected_ids(report, boundary):
    severe = [
        run for run in report["runs"]
        if run["expectedWarmEligibility"] and run["naturalCoverageDifference"] < boundary
    ]
    scenarios = {run["scenario"] for run in severe}
    controls = [
        run for run in report["runs"]
        if run["scenario"] in scenarios and run["learnerID"] == "learner-0"
    ]
    return sorted({run["runID"] for run in severe + controls})


def validate(manifest, root):
    require(manifest.get("schemaVersion") == 1, "unsupported schema")
    require(manifest.get("dataRole") == "diagnostic-development-forensic", "invalid data role")
    require(manifest.get("reservationStatus") == "frozen-not-executed", "reservation is not sealed")
    require(manifest.get("outcomes") is None, "unexecuted reservation contains outcomes")
    require(manifest.get("consumedAtRevision") is None, "unexecuted reservation is marked consumed")

    source = manifest["sourceEvidence"]
    report_path = root / source["report"]
    require(report_path.is_file(), "source report missing")
    require(
        hashlib.sha256(report_path.read_bytes()).hexdigest() == source["reportSHA256"],
        "source report checksum mismatch",
    )
    report = json.loads(report_path.read_text())
    rule = manifest["selectionRule"]
    require(rule["severeCaseBoundary"] == -0.05, "case boundary changed")
    require(rule["biasedSelectionAcknowledged"] is True, "biased selection is not acknowledged")
    expected = selected_ids(report, rule["severeCaseBoundary"])
    require(rule["selectedRunIDs"] == expected, "selected run IDs do not match the frozen rule")
    require(len(expected) == 11, "unexpected forensic support")

    trace = manifest["traceContract"]
    require(
        trace["paths"] == ["coldNatural", "warmNatural", "coldFixedBudget", "warmFixedBudget"],
        "trace paths changed",
    )
    require(trace["massConservationRequired"] is True, "mass conservation is not required")
    require(len(trace["perQuestionFields"]) == 14, "question trace fields changed")
    require(len(trace["requiredSummaries"]) == 5, "forensic summaries changed")
    require(manifest["decisionRule"]["noProductionChange"] is True, "production change permitted")
    require(manifest["decisionRule"]["noThresholdSelection"] is True, "threshold selection permitted")
    require(all(manifest["forbiddenAccess"].values()), "an access boundary was relaxed")


def self_test(manifest, root):
    validate(manifest, root)
    mutations = []
    changed_case = copy.deepcopy(manifest)
    changed_case["selectionRule"]["selectedRunIDs"].pop()
    mutations.append(changed_case)
    changed_boundary = copy.deepcopy(manifest)
    changed_boundary["selectionRule"]["severeCaseBoundary"] = -0.02
    mutations.append(changed_boundary)
    relaxed = copy.deepcopy(manifest)
    relaxed["forbiddenAccess"]["releaseHoldout"] = False
    mutations.append(relaxed)
    for mutation in mutations:
        try:
            validate(mutation, root)
        except ValidationError:
            continue
        raise AssertionError("invalid forensic manifest unexpectedly passed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    manifest = json.loads(args.manifest.read_text())
    if args.self_test:
        self_test(manifest, root)
        print("warm question-path forensic manifest self-test passed")
    else:
        validate(manifest, root)
        print("warm question-path forensic manifest valid")


if __name__ == "__main__":
    main()
