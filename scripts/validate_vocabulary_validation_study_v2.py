"""Relational fabricated-only vocabulary study schema v2 validation."""

from __future__ import annotations

import json
import math
import copy

TABLES = ("participants", "documents", "assessments", "itemPredictions", "criterionRecords", "questionTraces", "deckSnapshots", "samplingManifests", "retestManifests")
FORBIDDEN = {"documentTitle", "filePath", "path", "context", "rawDocumentText", "definition", "typedMeaning", "accountID", "exactTimestamp"}


def req(ok, message):
    if not ok:
        raise ValueError(f"dataset v2: {message}")


def walk(value):
    if isinstance(value, dict):
        req(not (set(value) & FORBIDDEN), f"forbidden fields {sorted(set(value) & FORBIDDEN)}")
        for child in value.values(): walk(child)
    elif isinstance(value, list):
        for child in value: walk(child)


def unique(rows, key):
    values = [row[key] for row in rows]
    req(all(isinstance(value, str) and value.strip() for value in values), f"empty {key}")
    req(len(values) == len(set(values)), f"duplicate {key}")
    return set(values)


def probability(value, name):
    req(isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and 0 <= value <= 1, f"invalid {name}")


def validate_dataset_v2(payload):
    walk(payload)
    req(payload.get("schemaVersion") == 2, "unsupported schema")
    req(payload.get("dataRole") == "fabricated-rehearsal", "not fabricated rehearsal")
    req(payload.get("realCollectionAuthorized") is False, "real collection must be false")
    req(payload.get("estimatorStatus") == "provisional-not-approved", "estimator status")
    for table in TABLES: req(isinstance(payload.get(table), list), f"missing table {table}")
    participants, documents, assessments = payload["participants"], payload["documents"], payload["assessments"]
    pids = unique(participants, "participantPseudonym"); dids = unique(documents, "opaqueStudyDocumentID"); aids = unique(assessments, "assessmentID")
    sampling = unique(payload["samplingManifests"], "samplingStageID"); retests = unique(payload["retestManifests"], "retestLinkageID")
    psplit = {row["participantPseudonym"]: row["analysisSplit"] for row in participants}
    dsplit = {row["opaqueStudyDocumentID"]: row["analysisSplit"] for row in documents}
    groups = {}
    for row in documents:
        group = row["nearDuplicateGroupID"]
        req(group not in groups or groups[group] == row["analysisSplit"], "near-duplicate split leakage")
        groups[group] = row["analysisSplit"]
    by_assessment = {}
    for row in assessments:
        req(row["participantPseudonym"] in pids and row["opaqueStudyDocumentID"] in dids, "broken assessment join")
        req(psplit[row["participantPseudonym"]] == dsplit[row["opaqueStudyDocumentID"]], "split leakage")
        req(0 <= row["questionCount"] <= 80, "question count")
        for name in ("expectedCurrentCoverage", "projectedCoverage", "conservativeCoverage"): probability(row[name], name)
        by_assessment[row["assessmentID"]] = row
    prediction_keys = set()
    for row in payload["itemPredictions"]:
        req(row["assessmentID"] in aids, "broken prediction join"); probability(row["finalKnownProbability"], "prediction")
        req(row["occurrenceCount"] > 0, "occurrence count")
        key = (row["assessmentID"], json.dumps(row["lexicalItemID"], sort_keys=True)); req(key not in prediction_keys, "duplicate prediction"); prediction_keys.add(key)
    doc_by_id = {row["opaqueStudyDocumentID"]: row for row in documents}
    for aid, assessment in by_assessment.items():
        if assessment["abandoned"]: continue
        rows = [row for row in payload["itemPredictions"] if row["assessmentID"] == aid and row["status"] != "excluded"]
        doc = doc_by_id[assessment["opaqueStudyDocumentID"]]
        req(len(rows) == doc["eligibleLexicalItemCount"] and sum(row["occurrenceCount"] for row in rows) == doc["eligibleOccurrenceMass"], "inventory denominator mismatch")
    for row in payload["criterionRecords"]:
        req(row["assessmentID"] in aids and row["samplingStageID"] in sampling, "broken criterion join"); probability(row["inclusionProbability"], "inclusion")
        req(row["inclusionProbability"] > 0, "zero inclusion")
        if row["status"] == "ambiguous": req(bool(row.get("ambiguityReason")), "ambiguous reason")
        if row["status"] == "missing": req(bool(row.get("missingnessReason")), "missing reason")
        if row["phase"] == "preReading": req(row.get("collectedBeforeReveal") is True, "post-reveal pre-reading criterion")
        if row["phase"] == "delayedRetest": req(row.get("retestLinkageID") in retests, "retest join")
    for row in payload["questionTraces"]:
        req(row["assessmentID"] in aids and row["questionOrdinal"] > 0 and row["revealedAfterResponse"] is True, "invalid question trace"); probability(row["predictedKnownBeforeAnswer"], "question prediction")
    available = {(row["assessmentID"], json.dumps(row["lexicalItemID"], sort_keys=True)) for row in payload["itemPredictions"]}
    for row in payload["deckSnapshots"]:
        req(row["assessmentID"] in aids, "broken deck join")
        req(all((row["assessmentID"], json.dumps(item, sort_keys=True)) in available for item in row["selectedLexicalItemIDs"]), "deck item missing")
    return {"schemaVersion": 2, **{table: len(payload[table]) for table in TABLES}}


def self_test_v2(payload):
    summary = validate_dataset_v2(payload)
    req(summary["assessments"] > 0, "empty rehearsal")
    mutations = []
    post_reveal = copy.deepcopy(payload)
    post_reveal["criterionRecords"][0]["collectedBeforeReveal"] = False
    mutations.append(post_reveal)
    missing_predictions = copy.deepcopy(payload)
    missing_predictions["itemPredictions"] = missing_predictions["itemPredictions"][1:]
    mutations.append(missing_predictions)
    broken_deck = copy.deepcopy(payload)
    broken_deck["deckSnapshots"][0]["selectedLexicalItemIDs"] = [{"language": "en", "lemma": "absent", "partOfSpeech": "noun"}]
    mutations.append(broken_deck)
    missing_retest = copy.deepcopy(payload)
    missing_retest["retestManifests"] = []
    mutations.append(missing_retest)
    for mutation in mutations:
        try:
            validate_dataset_v2(mutation)
        except ValueError:
            continue
        raise AssertionError("invalid v2 study package unexpectedly passed")
