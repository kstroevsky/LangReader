#!/usr/bin/env python3
"""Validate the blocked categorical-guardrail and independent-review packet."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "docs/plans/vocabulary-validation-evidence"
PRETEST = BASE / "pretest-interference-development-protocol-v3.json"
PRETEST_MD = BASE / "pretest-interference-development-protocol-v3.md"
CHECKLIST = BASE / "independent-review-decision-checklist-v1.json"
CHECKLIST_MD = BASE / "independent-review-decision-checklist-v1.md"


class ValidationError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ValidationError(message)


def git_bytes(revision, path):
    return subprocess.check_output(["git", "show", f"{revision}:{path}"], cwd=ROOT)


def validate(pretest, checklist, pretest_md, checklist_md):
    require(pretest.get("schemaVersion") == 3, "unsupported pretest v3")
    require(
        pretest.get("status") == "distribution-guardrail-required-collection-blocked",
        "pretest v3 status changed",
    )
    require(pretest["inheritAllV2Contracts"] is True, "v2 contracts not inherited")
    base = pretest["supersedesForFutureCollection"]
    require(
        hashlib.sha256((ROOT / base["path"]).read_bytes()).hexdigest() == base["sha256"],
        "pretest v2 checksum mismatch",
    )
    primary = pretest["primaryEndpoint"]
    require(primary["role"] == "primary equivalence endpoint", "primary role changed")
    require(primary["margin"] is None, "primary margin invented")
    guardrail = pretest["categoricalDistributionGuardrail"]
    require(guardrail["role"] == "decision-relevant equivalence guardrail", "guardrail demoted")
    require(guardrail["categories"] == ["I know it", "Not sure", "I don’t know"], "guardrail categories changed")
    require(guardrail["selectedMethod"] is None, "guardrail method invented")
    require(guardrail["totalVariationMargin"] is None, "TV margin invented")
    require(all(value is None for value in guardrail["categorySpecificMargins"].values()), "category margin invented")
    for key in ("estimator", "intervalOrJointRegion", "confidenceLevel", "multiplicityRelationToPrimary"):
        require(guardrail[key] is None, f"guardrail decision invented: {key}")
    decision = pretest["jointDecisionRule"]
    require(decision["guardrailMayBeDescriptiveOnly"] is False, "guardrail made descriptive")
    require("both satisfy" in decision["equivalenceSupported"], "joint pass rule weakened")
    require(all(value is None for value in pretest["actualStudyDecisionFieldsAddedByV3"].values()), "v3 study decision filled")
    require(all(value is False for value in pretest["accessBoundary"].values()), "v3 access boundary relaxed")

    require(checklist.get("schemaVersion") == 1, "unsupported checklist")
    require(
        checklist.get("status") == "ready-for-independent-review-decisions-unapproved",
        "checklist status changed",
    )
    revision = checklist["sourceRevision"]
    for source in checklist["lockedInputs"].values():
        require(
            hashlib.sha256(git_bytes(revision, source["path"])).hexdigest()
            == source["sha256"],
            f"checklist source lock mismatch: {source['path']}",
        )
    decisions = checklist["decisions"]
    require([item["id"] for item in decisions] == [f"REVIEW-{index:03d}" for index in range(1, 8)], "review IDs changed")
    require(all(item["value"] is None for item in decisions), "review decision silently filled")
    severity = next(item for item in decisions if item["id"] == "REVIEW-006")
    require(
        severity["identity"]
        == "conditionalTargetShortfall = (0.98 - c_severe) + conditionalThresholdExcessSeverity when c_severe < 0.98",
        "tail severity identity changed",
    )
    require(all(value is False for value in checklist["authorization"].values()), "review authorization overclaimed")

    for markdown, anchors in (
        (pretest_md, ("equivalence of the `I know it` rate alone is insufficient", "decision-relevant equivalence guardrail", "guardrail cannot be downgraded")),
        (checklist_md, ("misclassification/error treatment", "one formal conditional tail-severity endpoint", "Every decision value remains null")),
    ):
        for anchor in anchors:
            require(anchor in markdown, f"review markdown missing anchor: {anchor}")


def self_test(pretest, checklist, pretest_md, checklist_md):
    validate(pretest, checklist, pretest_md, checklist_md)
    descriptive = copy.deepcopy(pretest)
    descriptive["jointDecisionRule"]["guardrailMayBeDescriptiveOnly"] = True
    filled_method = copy.deepcopy(pretest)
    filled_method["categoricalDistributionGuardrail"]["selectedMethod"] = "total-variation-distance"
    approved = copy.deepcopy(checklist)
    approved["authorization"]["independentReviewCompleted"] = True
    for pretest_value, checklist_value in (
        (descriptive, checklist),
        (filled_method, checklist),
        (pretest, approved),
    ):
        try:
            validate(pretest_value, checklist_value, pretest_md, checklist_md)
        except ValidationError:
            continue
        raise AssertionError("invalid independent-review packet unexpectedly passed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    pretest = json.loads(PRETEST.read_text())
    checklist = json.loads(CHECKLIST.read_text())
    if args.self_test:
        self_test(pretest, checklist, PRETEST_MD.read_text(), CHECKLIST_MD.read_text())
        print("vocabulary independent-review decision packet self-test passed")
    else:
        validate(pretest, checklist, PRETEST_MD.read_text(), CHECKLIST_MD.read_text())
        print("vocabulary independent-review decision packet valid")


if __name__ == "__main__":
    main()
