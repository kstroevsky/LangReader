#!/usr/bin/env python3
"""Build the no-outcome categorical-guardrail review rehearsal."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "docs/plans/vocabulary-validation-evidence"
PROTOCOL = BASE / "pretest-interference-development-protocol-v3.json"
CHECKLIST = BASE / "independent-review-decision-checklist-v1.json"
SOURCE = BASE / "pretest-interference-fabricated-assignment-v2.json"
OUTPUT = BASE / "pretest-interference-fabricated-assignment-v3.json"


class ValidationError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ValidationError(message)


def build():
    protocol_bytes = PROTOCOL.read_bytes()
    checklist_bytes = CHECKLIST.read_bytes()
    source_bytes = SOURCE.read_bytes()
    protocol = json.loads(protocol_bytes)
    source = json.loads(source_bytes)
    assignments = []
    for row in source["assignments"]:
        updated = dict(row)
        updated.update({
            "firstStageCategory": None,
            "firstStageResponseMissing": None,
            "exclusionActionSelected": None,
            "knownClaimIndicator": None,
            "outcomeStatus": "not-collected-fabricated-rehearsal",
        })
        assignments.append(updated)
    guardrail = protocol["categoricalDistributionGuardrail"]
    return {
        "schemaVersion": 3,
        "dataRole": "fabricated-categorical-guardrail-schema-rehearsal",
        "realCollectionAuthorized": False,
        "outcomesIncluded": False,
        "protocol": str(PROTOCOL.relative_to(ROOT)),
        "protocolSHA256": hashlib.sha256(protocol_bytes).hexdigest(),
        "reviewChecklist": str(CHECKLIST.relative_to(ROOT)),
        "reviewChecklistSHA256": hashlib.sha256(checklist_bytes).hexdigest(),
        "sourceV2AssignmentSHA256": hashlib.sha256(source_bytes).hexdigest(),
        "knowledgeResponseCategories": guardrail["categories"],
        "exclusionAction": "Not a word/name",
        "guardrailDecision": {
            "selectedMethod": guardrail["selectedMethod"],
            "totalVariationMargin": guardrail["totalVariationMargin"],
            "categorySpecificMargins": guardrail["categorySpecificMargins"],
            "estimator": guardrail["estimator"],
            "intervalOrJointRegion": guardrail["intervalOrJointRegion"],
            "confidenceLevel": guardrail["confidenceLevel"],
            "multiplicityRelationToPrimary": guardrail["multiplicityRelationToPrimary"],
        },
        "jointDecision": "blocked-until-primary-and-distributional-equivalence-criteria-approved",
        "support": source["support"],
        "assignments": assignments,
    }


def validate(package):
    require(package.get("schemaVersion") == 3, "unsupported rehearsal schema")
    require(package.get("dataRole") == "fabricated-categorical-guardrail-schema-rehearsal", "invalid rehearsal role")
    require(package["realCollectionAuthorized"] is False and package["outcomesIncluded"] is False, "rehearsal authorized")
    require(package["protocolSHA256"] == hashlib.sha256(PROTOCOL.read_bytes()).hexdigest(), "protocol hash mismatch")
    require(package["reviewChecklistSHA256"] == hashlib.sha256(CHECKLIST.read_bytes()).hexdigest(), "checklist hash mismatch")
    require(package["sourceV2AssignmentSHA256"] == hashlib.sha256(SOURCE.read_bytes()).hexdigest(), "v2 source hash mismatch")
    require(package["knowledgeResponseCategories"] == ["I know it", "Not sure", "I don’t know"], "categories changed")
    require(package["exclusionAction"] == "Not a word/name", "exclusion action changed")
    decision = package["guardrailDecision"]
    require(decision["selectedMethod"] is None, "guardrail method invented")
    require(decision["totalVariationMargin"] is None, "TV margin invented")
    require(all(value is None for value in decision["categorySpecificMargins"].values()), "category margin invented")
    for key in ("estimator", "intervalOrJointRegion", "confidenceLevel", "multiplicityRelationToPrimary"):
        require(decision[key] is None, f"guardrail decision invented: {key}")
    require(
        package["jointDecision"]
        == "blocked-until-primary-and-distributional-equivalence-criteria-approved",
        "joint decision unblocked",
    )
    require(len(package["assignments"]) == 32, "assignment support changed")
    for row in package["assignments"]:
        for key in (
            "firstStageCategory", "firstStageResponseMissing",
            "exclusionActionSelected", "knownClaimIndicator",
        ):
            require(row[key] is None, f"fabricated outcome inserted: {key}")
        require(row["outcomeStatus"] == "not-collected-fabricated-rehearsal", "outcome status changed")
        require(row["productActions"] == ["I know it", "Not sure", "I don’t know", "Not a word/name"], "product actions changed")


def self_test(package):
    validate(package)
    selected = copy.deepcopy(package)
    selected["guardrailDecision"]["selectedMethod"] = "total-variation-distance"
    outcome = copy.deepcopy(package)
    outcome["assignments"][0]["firstStageCategory"] = "Not sure"
    descriptive = copy.deepcopy(package)
    descriptive["jointDecision"] = "primary-only"
    for mutation in (selected, outcome, descriptive):
        try:
            validate(mutation)
        except ValidationError:
            continue
        raise AssertionError("invalid independent-review rehearsal unexpectedly passed")


def encoded():
    package = build()
    validate(package)
    return (json.dumps(package, indent=2, sort_keys=True) + "\n").encode()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    expected = encoded()
    if args.check:
        if not OUTPUT.is_file() or OUTPUT.read_bytes() != expected:
            raise SystemExit(f"stale independent-review rehearsal: {OUTPUT.relative_to(ROOT)}")
        print("independent-review categorical guardrail rehearsal is current")
    else:
        OUTPUT.write_bytes(expected)
        print(f"generated {OUTPUT.relative_to(ROOT)}")
    if args.self_test:
        self_test(json.loads(expected))
        print("independent-review categorical guardrail rehearsal self-test passed")


if __name__ == "__main__":
    main()
