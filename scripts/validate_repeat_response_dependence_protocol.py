#!/usr/bin/env python3
"""Validate the blocked repeat-response dependence protocol."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "docs/plans/vocabulary-validation-evidence"
PROTOCOL = BASE / "repeat-response-dependence-protocol-v1.json"
MARKDOWN = BASE / "repeat-response-dependence-protocol-v1.md"


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
    require(protocol.get("dataRole") == "developmental-human-response-dependence-design", "invalid data role")
    lock = protocol["sourceLock"]
    for key in ("confirmationEvidence", "pilot", "interferenceProtocol"):
        source = lock[key]
        require(
            hashlib.sha256(git_bytes(lock["revision"], source["path"])).hexdigest()
            == source["sha256"],
            f"source lock mismatch: {key}",
        )

    sequence = protocol["sequence"]
    require([row["step"] for row in sequence] == [1, 2, 3, 4, 5], "sequence changed")
    require(sequence[0]["definitionOrCorrectnessFeedbackAvailable"] is False, "first response contaminated")
    require(sequence[1]["definitionOrCorrectnessFeedbackAvailable"] is False, "sealed response contaminated")
    require(sequence[2]["definitionOrCorrectnessFeedbackAvailable"] is True, "E1 lacks product reveal")

    reference = protocol["baselineKnowledgeReference"]
    require(reference["raters"] == 2 and reference["adjudicationRequired"] is True, "rater contract changed")
    require(reference["criterionAmbiguousSeparateFromMissing"] is True, "ambiguity collapsed")
    require(reference["selfVerificationDefinesK"] is False, "self-verification became ground truth")
    evidence = protocol["evidence"]
    require(evidence["knownSupportingCategories"] == ["verifiedKnown", "typedVerifiedKnown"], "known evidence changed")
    require(evidence["retainFullTransitionCategories"] is True, "transition categories collapsed")

    estimands = protocol["estimands"]
    require(
        estimands["primary"]
        == "p_persist = Pr(E2 supports known | E1 supports known, K = unknown, protocol)",
        "primary estimand changed",
    )
    require(estimands["derivedDetection"] == "p_detect = 1 - p_persist", "detection estimand changed")
    require(estimands["overallRowCountSubstitutesForPrimaryDenominator"] is False, "row count promoted")
    boundaries = protocol["analysisBoundaries"]
    require(boundaries["independenceAssumed"] is False, "response independence assumed")
    require(boundaries["firstRevealMayTeachOrCue"] is True, "reveal carryover hidden")
    require(boundaries["estimateMayTransferToDifferentDelayOrPrompt"] is False, "transportability overclaimed")
    require(boundaries["conditioningOnE1RequiresJointTransitionReporting"] is True, "joint transitions dropped")

    rehearsal = protocol["fabricatedRehearsal"]
    require(rehearsal == {
        "seed": 20260914,
        "records": 24,
        "outcomesIncluded": False,
        "realCollectionAuthorized": False,
    }, "fabricated rehearsal changed")
    for key, value in protocol["actualStudyDecisionFields"].items():
        require(value == [] if key == "namedApprovers" else value is None, f"unapproved decision filled: {key}")
    require(protocol["decisionUse"]["syntheticIndependentArmMayBeTreatedAsHumanEstimate"] is False, "synthetic independence promoted")
    require(protocol["decisionUse"]["fullyCorrelatedSyntheticArmMayBeTreatedAsHumanEstimate"] is False, "synthetic correlation promoted")
    require(protocol["decisionUse"]["automaticProductionActivation"] is False, "production activation enabled")
    require(all(value is False for value in protocol["accessBoundary"].values()), "access boundary relaxed")

    for anchor in (
        "p_persist = Pr(E2 supports known | E1 supports known, K = unknown, protocol)",
        "primary denominator of independent participant-item",
        "does not assume independent responses",
        "release-holdout access",
        "only after `p_persist` and burden are estimated",
    ):
        require(anchor in markdown, f"markdown missing anchor: {anchor}")


def self_test(protocol, markdown):
    validate(protocol, markdown)
    mutations = []
    independence = copy.deepcopy(protocol)
    independence["analysisBoundaries"]["independenceAssumed"] = True
    mutations.append(independence)
    filled_delay = copy.deepcopy(protocol)
    filled_delay["actualStudyDecisionFields"]["minimumDistractorItems"] = 5
    mutations.append(filled_delay)
    activated = copy.deepcopy(protocol)
    activated["decisionUse"]["automaticProductionActivation"] = True
    mutations.append(activated)
    for mutation in mutations:
        try:
            validate(mutation, markdown)
        except ValidationError:
            continue
        raise AssertionError("invalid repeat-response protocol unexpectedly passed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    protocol = json.loads(PROTOCOL.read_text())
    markdown = MARKDOWN.read_text()
    if args.self_test:
        self_test(protocol, markdown)
        print("repeat-response dependence protocol self-test passed")
    else:
        validate(protocol, markdown)
        print("repeat-response dependence protocol valid")


if __name__ == "__main__":
    main()
