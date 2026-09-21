#!/usr/bin/env python3
"""Generate and analyze a deterministic fabricated relational study package."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import tempfile
from pathlib import Path

from validate_vocabulary_validation_study_v2 import validate_dataset_v2


def lexical(language: str, lemma: str, pos: str) -> dict:
    return {"language": language, "lemma": lemma, "partOfSpeech": pos}


def build_package() -> dict:
    participants = [
        {"participantPseudonym": "fabricated-en-1", "consentProtocolVersion": "fabricated-consent-v1", "consentRecorded": True, "languageCode": "en", "l1LanguageCode": "de", "proficiencyBand": "B1/B2", "analysisSplit": "training", "cohort": "fabricated-census"},
        {"participantPseudonym": "fabricated-de-1", "consentProtocolVersion": "fabricated-consent-v1", "consentRecorded": True, "languageCode": "de", "l1LanguageCode": "en", "proficiencyBand": "B1/B2", "analysisSplit": "validation", "cohort": "fabricated-sample"},
    ]
    documents = [
        {"opaqueStudyDocumentID": "fabricated-en-small", "nearDuplicateGroupID": "near-en-1", "languageCode": "en", "genre": "news", "format": "pdf", "analysisSplit": "training", "inventorySnapshotID": "inventory-en-v1", "eligibleLexicalItemCount": 4, "eligibleOccurrenceMass": 100},
        {"opaqueStudyDocumentID": "fabricated-de-large", "nearDuplicateGroupID": "near-de-1", "languageCode": "de", "genre": "literary", "format": "epub", "analysisSplit": "validation", "inventorySnapshotID": "inventory-de-v1", "eligibleLexicalItemCount": 4, "eligibleOccurrenceMass": 100},
    ]
    items = {
        "en": [("bank", "noun", 40, 0.85, "known"), ("current", "adjective", 30, 0.20, "unknownOrPartial"), ("record", "verb", 20, 0.55, "ambiguous"), ("quiet", "adjective", 10, 0.75, "known")],
        "de": [("Bank", "noun", 45, 0.70, "known"), ("laufen", "verb", 25, 0.25, "unknownOrPartial"), ("Schloss", "noun", 20, 0.50, "ambiguous"), ("selten", "adjective", 10, 0.40, "missing")],
    }
    assessments = []
    predictions = []
    criteria = []
    questions = []
    decks = []
    retests = []
    for language, participant, document, split in [
        ("en", "fabricated-en-1", documents[0], "training"),
        ("de", "fabricated-de-1", documents[1], "validation"),
    ]:
        for order, condition in enumerate(("cold", "warm"), start=1):
            aid = f"assessment-{language}-{condition}"
            assessments.append({"assessmentID": aid, "participantPseudonym": participant, "opaqueStudyDocumentID": document["opaqueStudyDocumentID"], "condition": condition, "algorithmVersion": 3, "modelVersion": "rasch-knowledge-v1", "observationVersion": "categorical-evidence-v1", "resourceVersion": "fabricated-resource-v1", "priorUsed": condition == "warm", "priorEligible": condition == "warm", "questionCount": 4 if condition == "cold" else 2, "stopReason": "exhaustedCandidates", "abandoned": False, "lookupFailureCount": 1 if language == "de" else 0, "expectedCurrentCoverage": 0.65, "projectedCoverage": 0.99, "conservativeCoverage": 0.98, "sessionOrder": order})
            for index, (lemma, pos, weight, probability, status) in enumerate(items[language], start=1):
                item = lexical(language, lemma, pos)
                asked = index <= (4 if condition == "cold" else 2)
                predictions.append({"assessmentID": aid, "inventorySnapshotID": document["inventorySnapshotID"], "lexicalItemID": item, "finalKnownProbability": probability, "occurrenceCount": weight, "classification": "uncertain", "status": "asked" if asked else "unasked", **({"evidence": "verifiedKnown" if probability >= 0.5 else "reportedUnknown"} if asked else {})})
                if condition == "cold" and (language == "en" or index != 4):
                    criteria.append({"assessmentID": aid, "lexicalItemID": item, "phase": "preReading", "collectedBeforeReveal": True, "status": status, "firstRaterStatus": "known" if status in {"known", "ambiguous"} else "unknownOrPartial", "secondRaterStatus": "unknownOrPartial" if status == "ambiguous" else ("known" if status == "known" else "unknownOrPartial"), **({"adjudicatedStatus": "ambiguous", "ambiguityReason": "context-free multiple meanings"} if status == "ambiguous" else {}), **({"missingnessReason": "fabricated nonresponse"} if status == "missing" else {}), "rubricVersion": "fabricated-rubric-v1", "samplingStageID": f"sample-{language}", "inclusionProbability": 1.0 if language == "en" else (0.5 if index < 4 else 0.25)})
            selected = [lexical(language, items[language][1][0], items[language][1][1])]
            decks.append({"assessmentID": aid, "snapshotID": f"deck-{language}-{condition}-proposed", "role": "proposed", "inventorySnapshotID": document["inventorySnapshotID"], "selectedLexicalItemIDs": selected, "targetCoverage": 0.98, "expectedCoverage": 0.99, "conservativeCoverage": 0.98})
            decks.append({"assessmentID": aid, "snapshotID": f"deck-{language}-{condition}-edited", "role": "edited", "inventorySnapshotID": document["inventorySnapshotID"], "selectedLexicalItemIDs": selected + ([lexical(language, items[language][2][0], items[language][2][1])] if condition == "cold" else []), "targetCoverage": 0.98, "expectedCoverage": 1.0, "conservativeCoverage": 0.99})
            for ordinal in range(1, 3 if condition == "warm" else 5):
                lemma, pos, _, probability, _ = items[language][ordinal - 1]
                questions.append({"assessmentID": aid, "questionOrdinal": ordinal, "lexicalItemID": lexical(language, lemma, pos), "evidence": "verifiedKnown" if probability >= 0.5 else "reportedUnknown", "selectionType": "initialCalibration", "predictedKnownBeforeAnswer": 0.5, "revealedAfterResponse": True, "elapsedMilliseconds": 100 + ordinal})
            if condition == "cold":
                selected_item = selected[0]
                criteria.append({"assessmentID": aid, "lexicalItemID": selected_item, "phase": "immediatePostLearning", "collectedBeforeReveal": False, "status": "known", "firstRaterStatus": "known", "secondRaterStatus": "known", "rubricVersion": "fabricated-rubric-v1", "samplingStageID": f"sample-{language}", "inclusionProbability": 1.0 if language == "en" else 0.5})
                criteria.append({"assessmentID": aid, "lexicalItemID": selected_item, "phase": "delayedRetest", "collectedBeforeReveal": False, "status": "missing" if language == "de" else "known", **({"firstRaterStatus": "known", "secondRaterStatus": "known"} if language == "en" else {"missingnessReason": "fabricated attrition"}), "rubricVersion": "fabricated-rubric-v1", "samplingStageID": f"sample-{language}", "inclusionProbability": 1.0 if language == "en" else 0.5, "retestLinkageID": f"retest-{language}"})
                retests.append({"retestLinkageID": f"retest-{language}", "assessmentID": aid, "elapsedHours": 168, "windowVersion": "week-1-v1", "missingnessStatus": "observed" if language == "en" else "missing"})
    assessments.append({"assessmentID": "assessment-abandoned", "participantPseudonym": "fabricated-en-1", "opaqueStudyDocumentID": "fabricated-en-small", "condition": "cold", "algorithmVersion": 3, "modelVersion": "rasch-knowledge-v1", "observationVersion": "categorical-evidence-v1", "resourceVersion": "fabricated-resource-v1", "priorUsed": False, "priorEligible": False, "questionCount": 1, "abandoned": True, "lookupFailureCount": 1, "expectedCurrentCoverage": 0.5, "projectedCoverage": 0.5, "conservativeCoverage": 0.2, "sessionOrder": 3})
    return {"schemaVersion": 2, "dataRole": "fabricated-rehearsal", "realCollectionAuthorized": False, "studyProtocolVersion": "fabricated-protocol-v2", "rubricVersion": "fabricated-rubric-v1", "analysisConfigurationVersion": "descriptive-rehearsal-v1", "estimatorStatus": "provisional-not-approved", "participants": participants, "documents": documents, "assessments": assessments, "itemPredictions": predictions, "criterionRecords": criteria, "questionTraces": questions, "deckSnapshots": decks, "samplingManifests": [{"samplingStageID": "sample-en", "opaqueStudyDocumentID": "fabricated-en-small", "frameHash": "frame-en", "designVersion": "census-v1", "seed": 1, "census": True, "minimumInclusionProbability": 1.0, "maximumDesignWeight": 1.0, "weightBasedEffectiveSampleSize": 4.0, "expectedSelectedCardSupport": 1.0, "expectedFinalTailSupport": 2.0}, {"samplingStageID": "sample-de", "opaqueStudyDocumentID": "fabricated-de-large", "frameHash": "frame-de", "designVersion": "stratified-probability-v1", "seed": 2, "census": False, "minimumInclusionProbability": 0.25, "maximumDesignWeight": 4.0, "weightBasedEffectiveSampleSize": 2.0, "expectedSelectedCardSupport": 0.5, "expectedFinalTailSupport": 1.0}], "retestManifests": retests}


def analyze(package: dict) -> dict:
    predictions = {row["lexicalItemID"]["lemma"]: row["finalKnownProbability"] for row in package["itemPredictions"] if row["assessmentID"] == "assessment-en-cold"}
    truth = {"bank": 1.0, "current": 0.0, "quiet": 1.0}
    brier = sum((predictions[key] - value) ** 2 for key, value in truth.items()) / len(truth)
    expected_brier = ((0.85 - 1) ** 2 + (0.20 - 0) ** 2 + (0.75 - 1) ** 2) / 3
    assert math.isclose(brier, expected_brier, abs_tol=1e-15)
    return {"schemaVersion": 1, "status": "developmental-provisional", "estimatorStatus": "provisional-not-approved", "inputMap": {"itemCalibration": ["itemPredictions", "criterionRecords", "samplingManifests"], "deckValidity": ["deckSnapshots", "criterionRecords", "itemPredictions"], "burden": ["assessments", "questionTraces"], "retention": ["criterionRecords", "retestManifests"]}, "executed": {"smallDocumentCensusBrier": brier, "assessmentCount": len(package["assessments"]), "abandonedCount": sum(row["abandoned"] for row in package["assessments"]), "ambiguousCriterionCount": sum(row["status"] == "ambiguous" for row in package["criterionRecords"]), "missingCriterionCount": sum(row["status"] == "missing" for row in package["criterionRecords"])}, "nonEstimable": {"largeDocumentWeightedCoverage": "No approved estimator or variance method; inputs and design diagnostics are present.", "warmNonInferiority": "Fabricated support is insufficient and no approved margin/variance method exists.", "DIF": "Insufficient independent learners per item.", "humanThetaIntervalCoverage": "No justified independent human latent reference."}, "interpretation": "Fabricated rehearsal only; no participant data, confirmatory inference, or release claim."}


def markdown(analysis: dict) -> str:
    return "\n".join(["# Fabricated vocabulary study-package rehearsal", "", "Schema v2 is additive and fabricated-only. No estimator or interval method is approved.", "", f"Small-document census Brier (independently hand-checked): `{analysis['executed']['smallDocumentCensusBrier']:.6f}`.", "", "Large-document weighted coverage, warm non-inferiority, DIF, and human theta coverage remain explicitly non-estimable pending the reviewed SAP and adequate support.", ""])


def self_test() -> None:
    package = build_package(); validate_dataset_v2(package); analysis = analyze(package)
    assert analysis["executed"]["ambiguousCriterionCount"] == 2
    bad = copy.deepcopy(package); bad["realCollectionAuthorized"] = True
    try: validate_dataset_v2(bad); raise AssertionError("real collection passed")
    except ValueError: pass


def main() -> None:
    parser = argparse.ArgumentParser(); parser.add_argument("--package", type=Path); parser.add_argument("--analysis", type=Path); parser.add_argument("--markdown", type=Path); parser.add_argument("--self-test", action="store_true"); args = parser.parse_args()
    if args.self_test: self_test(); print("vocabulary validation-study rehearsal self-test passed"); return
    if not all((args.package, args.analysis, args.markdown)): parser.error("--package, --analysis and --markdown are required")
    package = build_package(); validate_dataset_v2(package); analysis = analyze(package)
    args.package.write_text(json.dumps(package, indent=2, sort_keys=True) + "\n"); args.analysis.write_text(json.dumps(analysis, indent=2, sort_keys=True) + "\n"); args.markdown.write_text(markdown(analysis))


if __name__ == "__main__": main()
