#!/usr/bin/env python3
"""Validate response-modality, evidence-event, denominator, and tail-name amendments."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "docs/plans/vocabulary-validation-evidence"
REVIEW = BASE / "protocol-alignment-forward-review-v1.json"
PRETEST = BASE / "pretest-interference-development-protocol-v2.json"
PRETEST_MD = BASE / "pretest-interference-development-protocol-v2.md"
REPEAT = BASE / "repeat-response-dependence-protocol-v2.json"
REPEAT_MD = BASE / "repeat-response-dependence-protocol-v2.md"
TAIL = BASE / "tail-risk-nomenclature-amendment-v1.json"
TAIL_MD = BASE / "tail-risk-nomenclature-amendment-v1.md"


class ValidationError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ValidationError(message)


def git_bytes(revision, path):
    return subprocess.check_output(["git", "show", f"{revision}:{path}"], cwd=ROOT)


def load(path):
    return json.loads(path.read_text())


def validate(review, pretest, repeat, tail, pretest_md, repeat_md, tail_md):
    require(review.get("schemaVersion") == 1, "unsupported review schema")
    require(
        review.get("status") == "audit-delta-implemented-independent-approval-pending",
        "review status overclaimed",
    )
    revision = review["sourceRevision"]
    for source in review["lockedSources"].values():
        require(
            hashlib.sha256(git_bytes(revision, source["path"])).hexdigest()
            == source["sha256"],
            f"alignment source lock mismatch: {source['path']}",
        )
    require([item["id"] for item in review["findings"]] == [
        "ALIGN-001", "ALIGN-002", "ALIGN-003", "ALIGN-004",
    ], "review findings changed")

    coordinator = git_bytes(
        revision,
        "Sources/LeafReaderApp/VocabularyReview/VocabularyPreparationCoordinator.swift",
    ).decode()
    view = git_bytes(
        revision,
        "Sources/LeafReaderApp/VocabularyReview/VocabularyPreparationView.swift",
    ).decode()
    for anchor in (
        'Button(AppText.localized("我认识", "I know it"))',
        'Button(AppText.localized("不确定", "Not sure"))',
        'Button(AppText.localized("我不认识", "I don’t know"))',
        'Button(AppText.localized("不是单词/是名称", "Not a word/name"))',
        'Button(AppText.localized("我的含义正确", "My meaning was correct"))',
        'Button(AppText.localized("不正确/只对了一部分", "No / only partly"))',
    ):
        require(anchor in view, f"production UI anchor missing: {anchor}")
    for anchor in (
        "interactionState = .pendingKnownVerification",
        "typedMeaning.isEmpty ? .verifiedKnown : .typedVerifiedKnown",
        ": .verifiedUnknownOrPartial",
        "recordEvidenceAndReveal(.reportedUnknown)",
        "recordEvidenceAndReveal(.unsure)",
    ):
        require(anchor in coordinator, f"production mapping anchor missing: {anchor}")

    require(pretest.get("schemaVersion") == 2, "unsupported pretest v2")
    require(pretest.get("status") == "modality-aligned-collection-blocked", "pretest v2 status changed")
    require(
        pretest["supersedesForFutureCollection"]["sha256"]
        == review["lockedSources"]["pretestProtocolV1"]["sha256"],
        "pretest v1 source mismatch",
    )
    probe = pretest["productProbe"]
    require(probe["modality"] == "actual-default-first-stage-categorical-ui", "product modality changed")
    require([item["uiLabel"] for item in probe["actions"]] == [
        "I know it", "Not sure", "I don’t know", "Not a word/name",
    ], "product actions changed")
    require(probe["typedMeaning"].startswith("optional"), "typed mode made mandatory")
    require(probe["primaryOutcome"] == "indicator that the first-stage action is known-claim", "pretest primary outcome changed")
    require(pretest["revealControl"]["definitionContextOrCorrectnessFeedbackBeforeBothTasks"] is False, "pretest feedback leakage")
    require(pretest["revealControl"]["knownClaimRevealDelayedUntilOtherTaskSealed"] is True, "pretest control reveal not delayed")
    require(pretest["criterionUse"]["categoricalKnownClaimTreatedAsMeaningCorrectness"] is False, "categorical response treated as correctness")
    require(all(value is None for value in pretest["actualStudyDecisionFieldsAddedByV2"].values()), "pretest v2 decision invented")
    require(all(value is False for value in pretest["accessBoundary"].values()), "pretest v2 access relaxed")

    require(repeat.get("schemaVersion") == 2, "unsupported repeat v2")
    require(repeat.get("status") == "production-event-aligned-collection-blocked", "repeat v2 status changed")
    require(
        repeat["supersedesForFutureCollection"]["sha256"]
        == review["lockedSources"]["repeatProtocolV1"]["sha256"],
        "repeat v1 source mismatch",
    )
    event = repeat["productionEventContract"]
    require(event["firstStageActions"] == [
        "I know it", "Not sure", "I don’t know", "Not a word/name",
    ], "repeat first-stage actions changed")
    require(event["knownClaimState"].startswith("pendingKnownVerification"), "pre-verification evidence recorded")
    require(event["evidenceMapping"] == [
        {"condition": "I know it; correct verification; typed meaning empty", "evidence": "verifiedKnown"},
        {"condition": "I know it; correct verification; typed meaning nonempty", "evidence": "typedVerifiedKnown"},
        {"condition": "I know it; incorrect/partial verification", "evidence": "verifiedUnknownOrPartial"},
        {"condition": "Not sure", "evidence": "unsure"},
        {"condition": "I don’t know", "evidence": "reportedUnknown"},
        {"condition": "Not a word/name", "evidence": "excluded"},
    ], "repeat evidence mapping changed")
    require(repeat["repeatContract"]["preSecondRevealIsNotUnaidedBaseline"] is True, "repeat carryover hidden")
    require(repeat["baselineKnowledgeReference"]["baselineKAcquisitionProtocolVersion"] is None, "K acquisition invented")
    denominator = repeat["primaryEstimand"]["primaryDenominator"]
    require(denominator.startswith("distinct eligible participant-item records"), "repeat denominator wording changed")
    require("independent participant-item" not in json.dumps(repeat), "repeat denominator still claims independence")
    require(repeat["primaryEstimand"]["independenceAssumed"] is False, "repeat independence assumed")
    require(all(value is None for value in repeat["actualStudyDecisionFieldsAddedByV2"].values()), "repeat v2 decision invented")
    require(all(value is False for value in repeat["accessBoundary"].values()), "repeat v2 access relaxed")

    require(tail.get("schemaVersion") == 1, "unsupported tail-name amendment")
    require(
        tail["baseContract"]["sha256"]
        == review["lockedSources"]["tailRiskContractV1"]["sha256"],
        "tail-risk base mismatch",
    )
    preserved = tail["preservedMetric"]
    require(preserved["existingIdentifier"] == "conditionalSevereExpectedShortfall", "existing metric removed")
    require(preserved["displayAlias"] == "conditionalTargetShortfall", "tail display alias changed")
    require(
        preserved["formula"]
        == "E[max(0, 0.98 - C_realized) | C_realized < c_severe]",
        "frozen target-shortfall formula changed",
    )
    require(preserved["mathematicalDefinitionChanged"] is False, "tail formula marked changed")
    optional = tail["separateOptionalMetric"]
    require(
        optional["formula"]
        == "E[c_severe - C_realized | C_realized < c_severe]",
        "threshold-excess formula changed",
    )
    require(optional["releaseRole"] is None and optional["numericalTolerance"] is None, "optional metric activated")
    require(all(value is False for value in tail["accessBoundary"].values()), "tail access boundary changed")

    for markdown, anchors in (
        (pretest_md, ("actual default first-stage", "Pr(known claim | criterion first)", "other task is sealed. This is an instrumentation deviation")),
        (repeat_md, ("complete production event", "pending verification and records no evidence", "distinct eligible participant-item records")),
        (tail_md, ("mathematical definition is unchanged", "conditionalTargetShortfall", "conditionalThresholdExcessSeverity")),
    ):
        for anchor in anchors:
            require(anchor in markdown, f"amendment markdown missing anchor: {anchor}")


def self_test(review, pretest, repeat, tail, pretest_md, repeat_md, tail_md):
    validate(review, pretest, repeat, tail, pretest_md, repeat_md, tail_md)
    mutations = []
    typed_only = copy.deepcopy(pretest)
    typed_only["productProbe"]["modality"] = "typed-meaning-only"
    mutations.append((typed_only, repeat, tail))
    missing_event = copy.deepcopy(repeat)
    missing_event["productionEventContract"]["evidenceMapping"].pop()
    mutations.append((pretest, missing_event, tail))
    changed_formula = copy.deepcopy(tail)
    changed_formula["preservedMetric"]["formula"] = "E[c_severe - C_realized]"
    mutations.append((pretest, repeat, changed_formula))
    for pretest_value, repeat_value, tail_value in mutations:
        try:
            validate(
                review,
                pretest_value,
                repeat_value,
                tail_value,
                pretest_md,
                repeat_md,
                tail_md,
            )
        except ValidationError:
            continue
        raise AssertionError("invalid protocol alignment amendment unexpectedly passed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    values = (
        load(REVIEW), load(PRETEST), load(REPEAT), load(TAIL),
        PRETEST_MD.read_text(), REPEAT_MD.read_text(), TAIL_MD.read_text(),
    )
    if args.self_test:
        self_test(*values)
        print("vocabulary protocol alignment amendments self-test passed")
    else:
        validate(*values)
        print("vocabulary protocol alignment amendments valid")


if __name__ == "__main__":
    main()
