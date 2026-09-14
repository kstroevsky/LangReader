#!/usr/bin/env python3
"""Validate the blocked developmental pretest-interference protocol."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROTOCOL = ROOT / "docs/plans/vocabulary-validation-evidence/pretest-interference-development-protocol-v1.json"
MARKDOWN = ROOT / "docs/plans/vocabulary-validation-evidence/pretest-interference-development-protocol-v1.md"


class ValidationError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ValidationError(message)


def git_bytes(revision, path):
    return subprocess.check_output(["git", "show", f"{revision}:{path}"], cwd=ROOT)


def validate(protocol, markdown):
    require(protocol.get("schemaVersion") == 1, "unsupported protocol schema")
    require(protocol.get("status") == "design-defined-collection-blocked", "protocol status changed")
    require(protocol.get("dataRole") == "developmental-human-study-design", "invalid data role")
    lock = protocol["sourceLock"]
    for key in ("pilot", "approvedDirections", "sapTemplate"):
        source = lock[key]
        actual = hashlib.sha256(git_bytes(lock["revision"], source["path"])).hexdigest()
        require(actual == source["sha256"], f"source lock mismatch: {key}")

    assignment = protocol["assignment"]
    require(assignment["withinParticipantDocument"] is True, "within-block randomization removed")
    require(assignment["ratio"] == "1:1", "assignment ratio changed")
    require(assignment["strata"] == ["predeclared frequency band", "part of speech"], "strata changed")
    require([arm["id"] for arm in assignment["arms"]] == [
        "criterion-before-product", "product-before-criterion",
    ], "assignment arms changed")
    require(assignment["actualRandomizationSeed"] is None, "actual seed invented")

    task = protocol["taskContract"]
    require(task["productResponseCapturedForEveryAssignedItem"] is True, "universal product response removed")
    require(task["definitionContextOrCorrectnessFeedbackBeforeBothResponses"] is False, "feedback leakage enabled")
    require(task["responseEditingAfterSecondTask"] is False, "response editing enabled")
    require(task["responsesEnterProductionCAT"] is False, "study response enters CAT")
    require(task["adaptiveSelectionUsed"] is False, "primary outcome conditioned on adaptive selection")

    scoring = protocol["scoring"]
    require(scoring["raters"] == 2, "rater count changed")
    require(scoring["adjudicationRequiredForDisagreement"] is True, "adjudication removed")
    require(scoring["criterionAmbiguousSeparateFromMissing"] is True, "ambiguity collapsed")
    require(scoring["leafReaderProbabilityOrDeckHiddenFromRaters"] is True, "rater blinding removed")

    estimand = protocol["estimand"]
    require(estimand["primary"].startswith("intention-to-treat difference"), "primary estimand changed")
    require(
        estimand["equivalenceDecision"]
        == "the approved confidence interval must lie wholly inside [-interferenceMargin, +interferenceMargin]",
        "equivalence rule changed",
    )
    require(estimand["conditioningOnProductResponseObserved"] is False, "post-assignment conditioning enabled")

    rehearsal = protocol["fabricatedRehearsal"]
    require(rehearsal == {
        "seed": 20260914,
        "participantDocumentBlocks": 4,
        "strataPerBlock": 4,
        "itemsPerStratum": 2,
        "outcomesIncluded": False,
        "realCollectionAuthorized": False,
    }, "fabricated rehearsal contract changed")
    decisions = protocol["actualStudyDecisionFields"]
    for key, value in decisions.items():
        require(value == [] if key == "namedApprovers" else value is None, f"unapproved decision filled: {key}")
    require(all(value is False for value in protocol["accessBoundary"].values()), "access boundary relaxed")
    require(protocol["privacy"]["separateExplicitConsentRequired"] is True, "consent requirement removed")
    require(protocol["privacy"]["automaticUpload"] is False, "automatic upload enabled")

    for anchor in (
        "criterion-before-product - product-before-criterion",
        "[-interferenceMargin, +interferenceMargin]",
        "Real collection additionally requires explicit consent",
        "development-confirmation",
        "release-holdout access remain outside this protocol",
    ):
        require(anchor in markdown, f"protocol markdown missing anchor: {anchor}")


def self_test(protocol, markdown):
    validate(protocol, markdown)
    mutations = []
    filled_margin = copy.deepcopy(protocol)
    filled_margin["actualStudyDecisionFields"]["practicallyMeaningfulInterferenceMargin"] = 0.02
    mutations.append(filled_margin)
    adaptive = copy.deepcopy(protocol)
    adaptive["taskContract"]["adaptiveSelectionUsed"] = True
    mutations.append(adaptive)
    authorized = copy.deepcopy(protocol)
    authorized["accessBoundary"]["realParticipantCollectionAuthorized"] = True
    mutations.append(authorized)
    for mutation in mutations:
        try:
            validate(mutation, markdown)
        except ValidationError:
            continue
        raise AssertionError("invalid pretest-interference protocol unexpectedly passed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    protocol = json.loads(PROTOCOL.read_text())
    markdown = MARKDOWN.read_text()
    if args.self_test:
        self_test(protocol, markdown)
        print("pretest-interference protocol self-test passed")
    else:
        validate(protocol, markdown)
        print("pretest-interference protocol valid")


if __name__ == "__main__":
    main()
