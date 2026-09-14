#!/usr/bin/env python3
"""Build and validate the no-outcome pretest-interference assignment rehearsal."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROTOCOL = ROOT / "docs/plans/vocabulary-validation-evidence/pretest-interference-development-protocol-v1.json"
OUTPUT = ROOT / "docs/plans/vocabulary-validation-evidence/pretest-interference-fabricated-assignment-v1.json"
ARMS = ("criterion-before-product", "product-before-criterion")
ORDERS = {
    "criterion-before-product": ["criterion response", "product-style response"],
    "product-before-criterion": ["product-style response", "criterion response"],
}


class ValidationError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ValidationError(message)


def build():
    protocol_bytes = PROTOCOL.read_bytes()
    protocol = json.loads(protocol_bytes)
    rehearsal = protocol["fabricatedRehearsal"]
    blocks = [
        ("fabricated-participant-01", "fabricated-document-01", "en"),
        ("fabricated-participant-02", "fabricated-document-02", "en"),
        ("fabricated-participant-03", "fabricated-document-03", "de"),
        ("fabricated-participant-04", "fabricated-document-04", "de"),
    ]
    strata = [
        ("high", "noun"),
        ("high", "verb"),
        ("low", "noun"),
        ("low", "verb"),
    ]
    assignments = []
    for block_index, (participant, document, language) in enumerate(blocks, 1):
        for stratum_index, (frequency, part_of_speech) in enumerate(strata, 1):
            token = f"{rehearsal['seed']}:{participant}:{document}:{frequency}:{part_of_speech}"
            first_arm = ARMS[hashlib.sha256(token.encode()).digest()[0] % 2]
            second_arm = ARMS[1 - ARMS.index(first_arm)]
            for item_index, arm in enumerate((first_arm, second_arm), 1):
                assignment_id = f"block-{block_index:02d}-stratum-{stratum_index:02d}-item-{item_index:02d}"
                assignments.append({
                    "assignmentID": assignment_id,
                    "participantPseudonym": participant,
                    "opaqueStudyDocumentID": document,
                    "languageCode": language,
                    "opaqueLexicalItemID": f"{document}-lexical-{stratum_index:02d}-{item_index:02d}",
                    "frequencyBand": frequency,
                    "partOfSpeech": part_of_speech,
                    "arm": arm,
                    "taskOrder": ORDERS[arm],
                    "eligibleFrameFrozenBeforeAssignment": True,
                    "strataFrozenBeforeAssignment": True,
                    "futureAssignmentsDisclosedToParticipant": False,
                    "definitionContextOrFeedbackBeforeBothResponses": False,
                })
    return {
        "schemaVersion": 1,
        "dataRole": "fabricated-assignment-rehearsal",
        "realCollectionAuthorized": False,
        "outcomesIncluded": False,
        "protocol": str(PROTOCOL.relative_to(ROOT)),
        "protocolSHA256": hashlib.sha256(protocol_bytes).hexdigest(),
        "seed": rehearsal["seed"],
        "support": {
            "participantDocumentBlocks": len(blocks),
            "strataPerBlock": len(strata),
            "itemsPerStratum": 2,
            "assignments": len(assignments),
        },
        "assignments": assignments,
    }


def validate(package):
    require(package.get("schemaVersion") == 1, "unsupported rehearsal schema")
    require(package.get("dataRole") == "fabricated-assignment-rehearsal", "invalid data role")
    require(package.get("realCollectionAuthorized") is False, "real collection authorized")
    require(package.get("outcomesIncluded") is False, "outcomes leaked into assignment rehearsal")
    require(package["protocol"] == str(PROTOCOL.relative_to(ROOT)), "protocol path changed")
    require(package["protocolSHA256"] == hashlib.sha256(PROTOCOL.read_bytes()).hexdigest(), "protocol checksum mismatch")
    require(package["seed"] == 20260914, "rehearsal seed changed")
    assignments = package["assignments"]
    require(len(assignments) == 32, "assignment support changed")
    require(len({row["assignmentID"] for row in assignments}) == len(assignments), "assignment ID repeated")
    require(len({row["opaqueLexicalItemID"] for row in assignments}) == len(assignments), "lexical item repeated")
    forbidden_fields = {
        "criterionResponse", "productResponse", "correct", "outcome",
        "documentText", "documentTitle", "documentPath", "definition", "context",
    }
    for row in assignments:
        require(row["arm"] in ARMS, "unknown assignment arm")
        require(row["taskOrder"] == ORDERS[row["arm"]], "task order mismatch")
        require(row["eligibleFrameFrozenBeforeAssignment"] is True, "frame not frozen")
        require(row["strataFrozenBeforeAssignment"] is True, "strata not frozen")
        require(row["futureAssignmentsDisclosedToParticipant"] is False, "allocation disclosed")
        require(row["definitionContextOrFeedbackBeforeBothResponses"] is False, "feedback leakage enabled")
        require(not (set(row) & forbidden_fields), "outcome/private field present")
    groups = {}
    for row in assignments:
        key = (
            row["participantPseudonym"], row["opaqueStudyDocumentID"],
            row["frequencyBand"], row["partOfSpeech"],
        )
        groups.setdefault(key, []).append(row)
    require(len(groups) == 16, "stratum block support changed")
    for rows in groups.values():
        require(Counter(row["arm"] for row in rows) == Counter(ARMS), "within-stratum balance failed")
    require(package["support"] == {
        "participantDocumentBlocks": 4,
        "strataPerBlock": 4,
        "itemsPerStratum": 2,
        "assignments": 32,
    }, "support summary mismatch")


def self_test(package):
    validate(package)
    mutations = []
    unbalanced = copy.deepcopy(package)
    unbalanced["assignments"][0]["arm"] = unbalanced["assignments"][1]["arm"]
    unbalanced["assignments"][0]["taskOrder"] = unbalanced["assignments"][1]["taskOrder"]
    mutations.append(unbalanced)
    leaked = copy.deepcopy(package)
    leaked["assignments"][0]["productResponse"] = "fabricated response"
    mutations.append(leaked)
    authorized = copy.deepcopy(package)
    authorized["realCollectionAuthorized"] = True
    mutations.append(authorized)
    for mutation in mutations:
        try:
            validate(mutation)
        except ValidationError:
            continue
        raise AssertionError("invalid pretest-interference rehearsal unexpectedly passed")


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
            raise SystemExit(f"stale pretest-interference rehearsal: {OUTPUT.relative_to(ROOT)}")
        print("pretest-interference assignment rehearsal is current")
    else:
        OUTPUT.write_bytes(expected)
        print(f"generated {OUTPUT.relative_to(ROOT)}")
    if args.self_test:
        self_test(json.loads(expected))
        print("pretest-interference assignment rehearsal self-test passed")


if __name__ == "__main__":
    main()
