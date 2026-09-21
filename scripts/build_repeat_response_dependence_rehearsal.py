#!/usr/bin/env python3
"""Build the no-outcome repeat-response schedule rehearsal."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROTOCOL = ROOT / "docs/plans/vocabulary-validation-evidence/repeat-response-dependence-protocol-v1.json"
OUTPUT = ROOT / "docs/plans/vocabulary-validation-evidence/repeat-response-dependence-fabricated-schedule-v1.json"


class ValidationError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ValidationError(message)


def build():
    protocol_bytes = PROTOCOL.read_bytes()
    protocol = json.loads(protocol_bytes)
    records = []
    for participant_index in range(1, 5):
        language = "en" if participant_index <= 2 else "de"
        participant = f"fabricated-repeat-participant-{participant_index:02d}"
        document = f"fabricated-repeat-document-{participant_index:02d}"
        for item_index in range(1, 7):
            record_id = f"repeat-{participant_index:02d}-{item_index:02d}"
            records.append({
                "recordID": record_id,
                "participantPseudonym": participant,
                "opaqueStudyDocumentID": document,
                "opaqueLexicalItemID": f"{document}-item-{item_index:02d}",
                "languageCode": language,
                "eventOrder": [
                    "first-product-response",
                    "seal-for-rater-scoring",
                    "definition-and-E1",
                    "distractor-block",
                    "repeat-confirmation-E2",
                ],
                "targetSenseContextHiddenFromParticipant": True,
                "futureE2ResponseUnavailableAtE1": True,
                "furtherTargetFeedbackBeforeE2": False,
                "confirmationPromptVersion": None,
                "definitionPresentationVersion": None,
                "minimumDistractorItems": None,
                "maximumConfirmationDelayMinutes": None,
                "scheduleStatus": "blocked-pending-approved-operational-values",
            })
    return {
        "schemaVersion": 1,
        "dataRole": "fabricated-repeat-response-schedule-rehearsal",
        "realCollectionAuthorized": False,
        "outcomesIncluded": False,
        "protocol": str(PROTOCOL.relative_to(ROOT)),
        "protocolSHA256": hashlib.sha256(protocol_bytes).hexdigest(),
        "seed": protocol["fabricatedRehearsal"]["seed"],
        "support": {
            "records": len(records),
            "participants": 4,
            "opaqueDocuments": 4,
            "languages": ["de", "en"],
        },
        "records": records,
    }


def validate(package):
    require(package.get("schemaVersion") == 1, "unsupported rehearsal schema")
    require(package.get("dataRole") == "fabricated-repeat-response-schedule-rehearsal", "invalid data role")
    require(package.get("realCollectionAuthorized") is False, "real collection authorized")
    require(package.get("outcomesIncluded") is False, "outcomes included")
    require(package["protocol"] == str(PROTOCOL.relative_to(ROOT)), "protocol path changed")
    require(package["protocolSHA256"] == hashlib.sha256(PROTOCOL.read_bytes()).hexdigest(), "protocol hash changed")
    require(package["seed"] == 20260914, "rehearsal seed changed")
    records = package["records"]
    require(len(records) == 24, "record support changed")
    require(len({row["recordID"] for row in records}) == 24, "record ID repeated")
    require(len({row["opaqueLexicalItemID"] for row in records}) == 24, "item ID repeated")
    expected_order = [
        "first-product-response", "seal-for-rater-scoring", "definition-and-E1",
        "distractor-block", "repeat-confirmation-E2",
    ]
    forbidden_fields = {
        "firstProductResponse", "K", "E1", "E2", "correct", "outcome",
        "definition", "targetSenseContext", "documentText", "documentTitle", "documentPath",
    }
    for row in records:
        require(row["eventOrder"] == expected_order, "event order changed")
        require(row["targetSenseContextHiddenFromParticipant"] is True, "target context exposed")
        require(row["futureE2ResponseUnavailableAtE1"] is True, "future response leakage")
        require(row["furtherTargetFeedbackBeforeE2"] is False, "target feedback inserted")
        for key in (
            "confirmationPromptVersion", "definitionPresentationVersion",
            "minimumDistractorItems", "maximumConfirmationDelayMinutes",
        ):
            require(row[key] is None, f"unapproved schedule value filled: {key}")
        require(row["scheduleStatus"] == "blocked-pending-approved-operational-values", "schedule unblocked")
        require(not (set(row) & forbidden_fields), "response/outcome/private field present")
    require(package["support"] == {
        "records": 24,
        "participants": 4,
        "opaqueDocuments": 4,
        "languages": ["de", "en"],
    }, "support summary changed")


def self_test(package):
    validate(package)
    mutations = []
    leaked = copy.deepcopy(package)
    leaked["records"][0]["E2"] = "verifiedKnown"
    mutations.append(leaked)
    reordered = copy.deepcopy(package)
    reordered["records"][0]["eventOrder"][2:4] = reversed(reordered["records"][0]["eventOrder"][2:4])
    mutations.append(reordered)
    invented = copy.deepcopy(package)
    invented["records"][0]["minimumDistractorItems"] = 5
    mutations.append(invented)
    for mutation in mutations:
        try:
            validate(mutation)
        except ValidationError:
            continue
        raise AssertionError("invalid repeat-response rehearsal unexpectedly passed")


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
            raise SystemExit(f"stale repeat-response rehearsal: {OUTPUT.relative_to(ROOT)}")
        print("repeat-response schedule rehearsal is current")
    else:
        OUTPUT.write_bytes(expected)
        print(f"generated {OUTPUT.relative_to(ROOT)}")
    if args.self_test:
        self_test(json.loads(expected))
        print("repeat-response schedule rehearsal self-test passed")


if __name__ == "__main__":
    main()
