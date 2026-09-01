#!/usr/bin/env python3
"""Validate explicit-consent vocabulary-study datasets without fitting them."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

SCHEMA_VERSION = 1
TOP_LEVEL_FIELDS = {
    "schemaVersion", "studyProtocolVersion", "consentProtocolVersion",
    "explicitConsentRecorded", "records",
}
RECORD_FIELDS = {
    "participantPseudonym", "opaqueStudyDocumentID", "languageCode",
    "lexicalItemID", "analysisSplit", "phase", "criterionLabel",
    "firstRaterLabel", "secondRaterLabel", "adjudicatedLabel",
    "randomizedAuditInclusionProbability", "questionAssignment",
    "delayedRetestLinkage",
}
LEXICAL_FIELDS = {"language", "lemma", "partOfSpeech", "senseKey"}
ASSIGNMENT_FIELDS = {
    "questionOrdinal", "selectionType", "predictedKnownBeforeAnswer",
    "thetaBinBeforeAnswer", "assignmentPolicyVersion",
}
SPLITS = {"training", "validation", "confirmatory"}
PHASES = {"preReading", "immediatePostLearning", "delayedRetest"}
LABELS = {"known", "unknownOrPartial"}
SELECTION_TYPES = {"initialCalibration", "adaptiveLoss", "tailValidation", "calibration"}
FORBIDDEN_FIELDS = {
    "documentID", "documentTitle", "title", "filePath", "path", "context",
    "rawDocumentText", "documentText", "definition", "typedMeaning",
    "accountID", "account", "exactTimestamp", "timestamp",
}


def require_exact_fields(payload: dict, allowed: set[str], required: set[str], location: str) -> None:
    unknown = set(payload) - allowed
    missing = required - set(payload)
    if unknown:
        raise ValueError(f"{location}: unsupported fields {sorted(unknown)}")
    if missing:
        raise ValueError(f"{location}: missing fields {sorted(missing)}")


def reject_forbidden_fields(value, location: str = "dataset") -> None:
    if isinstance(value, dict):
        forbidden = set(value) & FORBIDDEN_FIELDS
        if forbidden:
            raise ValueError(f"{location}: forbidden privacy fields {sorted(forbidden)}")
        for key, child in value.items():
            reject_forbidden_fields(child, f"{location}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            reject_forbidden_fields(child, f"{location}[{index}]")


def nonempty_string(value, location: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{location}: expected non-empty string")
    return value.strip()


def validate_dataset(payload: dict) -> dict:
    if not isinstance(payload, dict):
        raise ValueError("dataset: expected object")
    reject_forbidden_fields(payload)
    require_exact_fields(payload, TOP_LEVEL_FIELDS, TOP_LEVEL_FIELDS, "dataset")
    if payload["schemaVersion"] != SCHEMA_VERSION:
        raise ValueError("dataset: unsupported schemaVersion")
    nonempty_string(payload["studyProtocolVersion"], "dataset.studyProtocolVersion")
    nonempty_string(payload["consentProtocolVersion"], "dataset.consentProtocolVersion")
    if payload["explicitConsentRecorded"] is not True:
        raise ValueError("dataset: explicit consent was not recorded")
    if not isinstance(payload["records"], list):
        raise ValueError("dataset.records: expected array")

    participant_splits = {}
    document_splits = {}
    record_keys = set()
    assignment_count = 0
    delayed_count = 0
    for index, record in enumerate(payload["records"]):
        location = f"dataset.records[{index}]"
        if not isinstance(record, dict):
            raise ValueError(f"{location}: expected object")
        required = RECORD_FIELDS - {"adjudicatedLabel", "questionAssignment", "delayedRetestLinkage"}
        require_exact_fields(record, RECORD_FIELDS, required, location)
        participant = nonempty_string(record["participantPseudonym"], f"{location}.participantPseudonym")
        document = nonempty_string(record["opaqueStudyDocumentID"], f"{location}.opaqueStudyDocumentID")
        nonempty_string(record["languageCode"], f"{location}.languageCode")
        split = record["analysisSplit"]
        phase = record["phase"]
        if split not in SPLITS:
            raise ValueError(f"{location}.analysisSplit: invalid value")
        if phase not in PHASES:
            raise ValueError(f"{location}.phase: invalid value")

        lexical = record["lexicalItemID"]
        if not isinstance(lexical, dict):
            raise ValueError(f"{location}.lexicalItemID: expected object")
        require_exact_fields(
            lexical, LEXICAL_FIELDS, {"language", "lemma", "partOfSpeech"},
            f"{location}.lexicalItemID",
        )
        lexical_parts = [
            nonempty_string(lexical[field], f"{location}.lexicalItemID.{field}")
            for field in ("language", "lemma", "partOfSpeech")
        ]
        sense = lexical.get("senseKey")
        if sense is not None:
            lexical_parts.append(nonempty_string(sense, f"{location}.lexicalItemID.senseKey"))

        criterion = record["criterionLabel"]
        first = record["firstRaterLabel"]
        second = record["secondRaterLabel"]
        adjudicated = record.get("adjudicatedLabel")
        if criterion not in LABELS or first not in LABELS or second not in LABELS:
            raise ValueError(f"{location}: invalid criterion/rater label")
        if adjudicated is not None and adjudicated not in LABELS:
            raise ValueError(f"{location}.adjudicatedLabel: invalid value")
        expected = adjudicated if adjudicated is not None else first
        if first != second and adjudicated is None:
            raise ValueError(f"{location}: rater disagreement needs adjudication")
        if criterion != expected:
            raise ValueError(f"{location}: criterion does not match rater/adjudication labels")

        probability = record["randomizedAuditInclusionProbability"]
        if isinstance(probability, bool) or not isinstance(probability, (int, float)) or not 0 < probability <= 1:
            raise ValueError(f"{location}.randomizedAuditInclusionProbability: expected (0, 1]")

        assignment = record.get("questionAssignment")
        if assignment is not None:
            assignment_count += 1
            if not isinstance(assignment, dict):
                raise ValueError(f"{location}.questionAssignment: expected object")
            require_exact_fields(
                assignment, ASSIGNMENT_FIELDS, ASSIGNMENT_FIELDS,
                f"{location}.questionAssignment",
            )
            ordinal = assignment["questionOrdinal"]
            predicted = assignment["predictedKnownBeforeAnswer"]
            if isinstance(ordinal, bool) or not isinstance(ordinal, int) or ordinal <= 0:
                raise ValueError(f"{location}.questionAssignment.questionOrdinal: expected positive integer")
            if isinstance(predicted, bool) or not isinstance(predicted, (int, float)) or not 0 <= predicted <= 1:
                raise ValueError(f"{location}.questionAssignment.predictedKnownBeforeAnswer: expected [0, 1]")
            if assignment["selectionType"] not in SELECTION_TYPES:
                raise ValueError(f"{location}.questionAssignment.selectionType: invalid value")
            nonempty_string(assignment["thetaBinBeforeAnswer"], f"{location}.questionAssignment.thetaBinBeforeAnswer")
            nonempty_string(assignment["assignmentPolicyVersion"], f"{location}.questionAssignment.assignmentPolicyVersion")

        delayed_link = record.get("delayedRetestLinkage")
        if phase == "delayedRetest":
            delayed_count += 1
            nonempty_string(delayed_link, f"{location}.delayedRetestLinkage")
        elif delayed_link is not None:
            nonempty_string(delayed_link, f"{location}.delayedRetestLinkage")

        if participant in participant_splits and participant_splits[participant] != split:
            raise ValueError(f"{location}: participant appears in multiple analysis splits")
        participant_splits[participant] = split
        if document in document_splits and document_splits[document] != split:
            raise ValueError(f"{location}: document appears in multiple analysis splits")
        document_splits[document] = split
        record_key = (participant, document, *lexical_parts, phase, delayed_link or "")
        if record_key in record_keys:
            raise ValueError(f"{location}: duplicate record")
        record_keys.add(record_key)

    return {
        "schemaVersion": SCHEMA_VERSION,
        "records": len(payload["records"]),
        "participants": len(participant_splits),
        "documents": len(document_splits),
        "questionAssignments": assignment_count,
        "delayedRetests": delayed_count,
        "splitCounts": {
            split: sum(1 for record in payload["records"] if record["analysisSplit"] == split)
            for split in sorted(SPLITS)
        },
    }


def self_test() -> None:
    record = {
        "participantPseudonym": "p-1",
        "opaqueStudyDocumentID": "d-1",
        "languageCode": "en",
        "lexicalItemID": {"language": "en", "lemma": "develop", "partOfSpeech": "verb"},
        "analysisSplit": "training",
        "phase": "preReading",
        "criterionLabel": "known",
        "firstRaterLabel": "known",
        "secondRaterLabel": "known",
        "randomizedAuditInclusionProbability": 0.25,
        "questionAssignment": {
            "questionOrdinal": 15,
            "selectionType": "tailValidation",
            "predictedKnownBeforeAnswer": 0.91,
            "thetaBinBeforeAnswer": "bin-7",
            "assignmentPolicyVersion": "study-assignment-v1",
        },
    }
    payload = {
        "schemaVersion": 1,
        "studyProtocolVersion": "pilot-v1",
        "consentProtocolVersion": "consent-v1",
        "explicitConsentRecorded": True,
        "records": [record],
    }
    assert validate_dataset(payload)["questionAssignments"] == 1

    invalid = json.loads(json.dumps(payload))
    invalid["records"][0]["documentTitle"] = "private title"
    try:
        validate_dataset(invalid)
        raise AssertionError("forbidden document title was accepted")
    except ValueError as error:
        assert "forbidden privacy fields" in str(error)

    leaked = json.loads(json.dumps(payload))
    leaked["records"].append({
        **record,
        "opaqueStudyDocumentID": "d-2",
        "analysisSplit": "confirmatory",
    })
    try:
        validate_dataset(leaked)
        raise AssertionError("participant split leakage was accepted")
    except ValueError as error:
        assert "participant appears in multiple" in str(error)
    print("vocabulary validation-study dataset self-test passed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("datasets", nargs="*", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if not args.datasets:
        parser.error("provide at least one consented study dataset")
    participant_splits = {}
    document_splits = {}
    record_keys = set()
    summaries = []
    for path in args.datasets:
        payload = json.loads(path.read_text(encoding="utf-8"))
        summary = validate_dataset(payload)
        summaries.append({"path": str(path), **summary})
        for record in payload["records"]:
            participant = record["participantPseudonym"].strip()
            document = record["opaqueStudyDocumentID"].strip()
            split = record["analysisSplit"]
            if participant in participant_splits and participant_splits[participant] != split:
                raise ValueError(f"{path}: participant appears across dataset splits")
            if document in document_splits and document_splits[document] != split:
                raise ValueError(f"{path}: document appears across dataset splits")
            participant_splits[participant] = split
            document_splits[document] = split
            record_key = (
                participant,
                document,
                json.dumps(record["lexicalItemID"], sort_keys=True),
                record["phase"],
                record.get("delayedRetestLinkage") or "",
            )
            if record_key in record_keys:
                raise ValueError(f"{path}: duplicate record across datasets")
            record_keys.add(record_key)
    print(json.dumps({"datasets": summaries}, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
