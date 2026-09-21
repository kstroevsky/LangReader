#!/usr/bin/env python3
"""Build no-outcome rehearsals for the response-aligned v2 study protocols."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "docs/plans/vocabulary-validation-evidence"
PRETEST_PROTOCOL = BASE / "pretest-interference-development-protocol-v2.json"
REPEAT_PROTOCOL = BASE / "repeat-response-dependence-protocol-v2.json"
PRETEST_V1 = BASE / "pretest-interference-fabricated-assignment-v1.json"
REPEAT_V1 = BASE / "repeat-response-dependence-fabricated-schedule-v1.json"
PRETEST_OUTPUT = BASE / "pretest-interference-fabricated-assignment-v2.json"
REPEAT_OUTPUT = BASE / "repeat-response-dependence-fabricated-schedule-v2.json"


class ValidationError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ValidationError(message)


def build_pretest():
    protocol_bytes = PRETEST_PROTOCOL.read_bytes()
    source = json.loads(PRETEST_V1.read_text())
    order = {
        "criterion-before-product": ["criterion task", "product first-stage probe"],
        "product-before-criterion": ["product first-stage probe", "criterion task"],
    }
    assignments = []
    for row in source["assignments"]:
        updated = dict(row)
        updated.update({
            "taskOrder": order[row["arm"]],
            "criterionResponseModality": "context-free meanings-or-translations",
            "productResponseModality": "actual-default-first-stage-categorical-ui",
            "productActions": ["I know it", "Not sure", "I don’t know", "Not a word/name"],
            "typedMeaningOptional": True,
            "primaryOutcome": "first-stage-known-claim-indicator",
            "knownClaimRevealDelayedUntilOtherTaskSealed": True,
        })
        assignments.append(updated)
    return {
        "schemaVersion": 2,
        "dataRole": "fabricated-modality-aligned-assignment-rehearsal",
        "realCollectionAuthorized": False,
        "outcomesIncluded": False,
        "protocol": str(PRETEST_PROTOCOL.relative_to(ROOT)),
        "protocolSHA256": hashlib.sha256(protocol_bytes).hexdigest(),
        "sourceV1AssignmentSHA256": hashlib.sha256(PRETEST_V1.read_bytes()).hexdigest(),
        "support": source["support"],
        "assignments": assignments,
    }


def build_repeat():
    protocol_bytes = REPEAT_PROTOCOL.read_bytes()
    source = json.loads(REPEAT_V1.read_text())
    event_order = [
        "E1-first-stage-action",
        "E1-optional-typed-meaning-sealed",
        "E1-definition-reveal-if-known-claim",
        "E1-post-reveal-verification-if-known-claim",
        "E1-final-evidence-mapped",
        "distractor-block",
        "E2-first-stage-action",
        "E2-optional-typed-meaning-sealed",
        "E2-definition-reveal-if-known-claim",
        "E2-post-reveal-verification-if-known-claim",
        "E2-final-evidence-mapped",
    ]
    records = []
    for row in source["records"]:
        updated = dict(row)
        updated.update({
            "eventOrder": event_order,
            "firstStageActions": ["I know it", "Not sure", "I don’t know", "Not a word/name"],
            "typedMeaningOptionalOnE1AndE2": True,
            "E1AndE2AreCompleteProductionEvents": True,
            "preSecondRevealIsUnaidedBaseline": False,
            "baselineKAcquisitionProtocolVersion": None,
            "productionUIContractRevision": None,
            "evidenceMappingRevision": None,
            "E2FullInteractionVersion": None,
        })
        records.append(updated)
    protocol = json.loads(protocol_bytes)
    return {
        "schemaVersion": 2,
        "dataRole": "fabricated-production-event-aligned-repeat-schedule",
        "realCollectionAuthorized": False,
        "outcomesIncluded": False,
        "protocol": str(REPEAT_PROTOCOL.relative_to(ROOT)),
        "protocolSHA256": hashlib.sha256(protocol_bytes).hexdigest(),
        "sourceV1ScheduleSHA256": hashlib.sha256(REPEAT_V1.read_bytes()).hexdigest(),
        "primaryDenominator": protocol["primaryEstimand"]["primaryDenominator"],
        "evidenceMapping": protocol["productionEventContract"]["evidenceMapping"],
        "support": source["support"],
        "records": records,
    }


def validate_pretest(package):
    require(package.get("schemaVersion") == 2, "unsupported pretest rehearsal")
    require(package.get("dataRole") == "fabricated-modality-aligned-assignment-rehearsal", "invalid pretest role")
    require(package["realCollectionAuthorized"] is False and package["outcomesIncluded"] is False, "pretest rehearsal authorized")
    require(package["protocolSHA256"] == hashlib.sha256(PRETEST_PROTOCOL.read_bytes()).hexdigest(), "pretest protocol hash mismatch")
    require(package["sourceV1AssignmentSHA256"] == hashlib.sha256(PRETEST_V1.read_bytes()).hexdigest(), "pretest v1 source mismatch")
    require(len(package["assignments"]) == 32, "pretest support changed")
    for row in package["assignments"]:
        require(row["productResponseModality"] == "actual-default-first-stage-categorical-ui", "modality regressed")
        require(row["productActions"] == ["I know it", "Not sure", "I don’t know", "Not a word/name"], "actions changed")
        require(row["typedMeaningOptional"] is True, "typed mode changed")
        require(row["primaryOutcome"] == "first-stage-known-claim-indicator", "primary outcome changed")
        require(row["knownClaimRevealDelayedUntilOtherTaskSealed"] is True, "reveal control changed")
        require(row["definitionContextOrFeedbackBeforeBothResponses"] is False, "feedback leakage")
        require(not ({"productResponse", "criterionResponse", "outcome"} & set(row)), "pretest outcomes leaked")


def validate_repeat(package):
    require(package.get("schemaVersion") == 2, "unsupported repeat rehearsal")
    require(package.get("dataRole") == "fabricated-production-event-aligned-repeat-schedule", "invalid repeat role")
    require(package["realCollectionAuthorized"] is False and package["outcomesIncluded"] is False, "repeat rehearsal authorized")
    require(package["protocolSHA256"] == hashlib.sha256(REPEAT_PROTOCOL.read_bytes()).hexdigest(), "repeat protocol hash mismatch")
    require(package["sourceV1ScheduleSHA256"] == hashlib.sha256(REPEAT_V1.read_bytes()).hexdigest(), "repeat v1 source mismatch")
    require(package["primaryDenominator"].startswith("distinct eligible participant-item records"), "denominator regressed")
    require(len(package["evidenceMapping"]) == 6, "evidence mapping incomplete")
    require(len(package["records"]) == 24, "repeat support changed")
    for row in package["records"]:
        require(len(row["eventOrder"]) == 11, "full E1/E2 schedule incomplete")
        require(row["E1AndE2AreCompleteProductionEvents"] is True, "full production event removed")
        require(row["preSecondRevealIsUnaidedBaseline"] is False, "E2 mislabeled unaided")
        require(row["typedMeaningOptionalOnE1AndE2"] is True, "typed option changed")
        for key in (
            "baselineKAcquisitionProtocolVersion", "productionUIContractRevision",
            "evidenceMappingRevision", "E2FullInteractionVersion",
            "minimumDistractorItems", "maximumConfirmationDelayMinutes",
        ):
            require(row[key] is None, f"repeat decision invented: {key}")
        require(not ({"K", "E1", "E2", "outcome"} & set(row)), "repeat outcomes leaked")


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def self_test(pretest, repeat):
    validate_pretest(pretest)
    validate_repeat(repeat)
    bad_pretest = copy.deepcopy(pretest)
    bad_pretest["assignments"][0]["productResponseModality"] = "typed-only"
    bad_repeat = copy.deepcopy(repeat)
    bad_repeat["records"][0]["eventOrder"].pop()
    leaked_repeat = copy.deepcopy(repeat)
    leaked_repeat["records"][0]["E1"] = "verifiedKnown"
    for package, validator in (
        (bad_pretest, validate_pretest),
        (bad_repeat, validate_repeat),
        (leaked_repeat, validate_repeat),
    ):
        try:
            validator(package)
        except ValidationError:
            continue
        raise AssertionError("invalid aligned rehearsal unexpectedly passed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    pretest = build_pretest()
    repeat = build_repeat()
    validate_pretest(pretest)
    validate_repeat(repeat)
    outputs = ((PRETEST_OUTPUT, encoded(pretest)), (REPEAT_OUTPUT, encoded(repeat)))
    if args.check:
        for path, expected in outputs:
            if not path.is_file() or path.read_bytes() != expected:
                raise SystemExit(f"stale aligned protocol rehearsal: {path.relative_to(ROOT)}")
        print("aligned vocabulary protocol rehearsals are current")
    else:
        for path, expected in outputs:
            path.write_bytes(expected)
            print(f"generated {path.relative_to(ROOT)}")
    if args.self_test:
        self_test(pretest, repeat)
        print("aligned vocabulary protocol rehearsal self-test passed")


if __name__ == "__main__":
    main()
