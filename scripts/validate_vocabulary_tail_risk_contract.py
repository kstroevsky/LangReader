#!/usr/bin/env python3
"""Validate the additive vocabulary realized tail-risk definition contract."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "docs/plans/vocabulary-validation-evidence"
SOURCE_LOCK = BASE / "tail-risk-acceptance-source-lock-v1.json"
DELTA = BASE / "tail-risk-acceptance-delta-v1.json"
LEDGER = BASE / "tail-risk-acceptance-ledger-v1.json"
CONTRACT = BASE / "tail-risk-acceptance-semantics-v1.json"
MARKDOWN = BASE / "tail-risk-acceptance-semantics-v1.md"
VERIFICATION = BASE / "tail-risk-acceptance-verification-v1.json"
REVISION_STATE = BASE / "tail-risk-acceptance-revision-state-v1.json"


class ValidationError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ValidationError(message)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def load(path):
    return json.loads(path.read_text())


def git_bytes(revision, path):
    return subprocess.check_output(
        ["git", "show", f"{revision}:{path}"],
        cwd=ROOT,
    )


def validate(source_lock, delta, ledger, contract, markdown, verification, revision_state):
    require(source_lock.get("schemaVersion") == 1, "unsupported source lock")
    revision = source_lock["sourceRevision"]
    require(len(revision) == 40, "source revision is not immutable")
    for source in source_lock["sources"]:
        require(
            sha256(git_bytes(revision, source["path"])) == source["sha256"],
            f"source lock mismatch: {source['path']}",
        )
    preservation = source_lock["preservation"]
    require(
        preservation == {
            "implementationPlanModified": False,
            "canonicalLedgerModified": False,
            "sapTemplateModified": False,
            "risk001Status": "deferred",
            "productionRiskCalibrationEnabled": False,
        },
        "source preservation boundary changed",
    )

    canonical = json.loads(git_bytes(
        revision,
        "docs/plans/vocabulary-measurement-coherence/target-ledger.json",
    ))
    canonical_by_id = {item["id"]: item for item in canonical["requirements"]}
    require(len(canonical_by_id) == 54, "canonical requirement count changed at source")
    require(canonical_by_id["RISK-001"]["status"] == "deferred", "RISK-001 was activated")
    require(canonical_by_id["RISK-001"]["normative_payload"]["production_enabled"] is False, "risk calibration enabled")
    require(canonical_by_id["COV-001"]["normative_payload"]["reported_quantile"] == 0.05, "coverage quantile changed")
    require(canonical_by_id["EVAL-001"]["normative_payload"]["warm_coverage_degradation_max_pp"] == 2, "development materiality changed")

    require(delta.get("schemaVersion") == 1 and delta.get("closedWorld") is True, "delta is not closed-world")
    require(delta["sourceLock"] == str(SOURCE_LOCK.relative_to(ROOT)), "delta source lock changed")
    require(all(change["operation"] == "ADD" for change in delta["changes"]), "base amendment introduced")
    require(set(delta["noChange"]) == {
        "production CAT", "production posterior-predictive fifth-percentile rule",
        "canonical EVAL-001 gates", "deferred RISK-001 status",
        "development-confirmation reservation", "release holdout", "SAP approval status",
    }, "no-change boundary changed")

    require(ledger.get("schemaVersion") == 1, "unsupported tail-risk ledger")
    requirements = ledger["requirements"]
    ids = [item["id"] for item in requirements]
    require(ids == [f"TRISK-{index:03d}" for index in range(1, 13)], "tail-risk requirement IDs changed")
    require(sum(item["status"] == "active" for item in requirements) == 10, "active count changed")
    require(sum(item["status"] == "deferred" for item in requirements) == 2, "deferred count changed")
    delta_ids = {
        requirement_id
        for change in delta["changes"]
        for requirement_id in change["requirementIDs"]
    }
    require(delta_ids == set(ids), "delta does not cover the tail-risk ledger exactly")

    require(contract.get("schemaVersion") == 1, "unsupported contract schema")
    require(contract.get("status") == "definitions-frozen-release-decision-blocked", "contract status changed")
    require(contract["sourceLock"] == str(SOURCE_LOCK.relative_to(ROOT)), "contract source lock changed")
    require(contract["delta"] == str(DELTA.relative_to(ROOT)), "contract delta changed")
    require(contract["ledger"] == str(LEDGER.relative_to(ROOT)), "contract ledger changed")
    require(contract["claimBoundary"]["posteriorPredictive"]["formula"] == "Q_0.05(C | E) >= 0.98", "predictive claim changed")
    require(contract["claimBoundary"]["realizedTailRisk"]["unit"] == "learner-document assessment", "analysis unit changed")
    require(contract["claimBoundary"]["realizedTailRisk"]["shortfall"] == "L = max(0, 0.98 - C_realized)", "shortfall changed")
    severe = contract["tailMetrics"]["severeMissRate"]
    require(severe["formula"] == "P_severe(c_severe) = Pr(C_realized < c_severe)", "severe-rate formula changed")
    require(severe["releaseSevereCoverageThreshold"] is None, "release severe threshold invented")
    require(severe["developmentReferenceCoverage"] == 0.96, "development reference changed")
    require("not a release gate" in severe["developmentReferenceRole"], "development reference promoted")
    conditional = contract["tailMetrics"]["conditionalSevereExpectedShortfall"]
    require(conditional["formula"] == "ES_severe(c_severe) = E[L | C_realized < c_severe]", "conditional shortfall changed")
    require(conditional["zeroSevereEventConvention"].startswith("not estimable"), "zero-event severity invented")

    release_fields = contract["releaseDecisionFields"]
    required_nulls = {
        "tailComponentsRequiredForRelease", "releaseSevereCoverageThreshold",
        "maximumSevereMissRate", "maximumConditionalSevereExpectedShortfall",
        "maximumUnconditionalMeanShortfall", "estimator", "intervalConstruction",
        "confidenceLevel", "multiplicityRule", "approvalRevision",
    }
    require(all(release_fields[key] is None for key in required_nulls), "unapproved release value filled")
    require(release_fields["approvers"] == [], "unapproved approver recorded")
    require(contract["warmComparisonContract"]["tailNonInferiorityMargins"] is None, "tail margin invented")
    require(contract["humanEstimationContract"]["rowCountMayReplaceIndependentSupport"] is False, "row count promoted")
    require(contract["humanEstimationContract"]["zeroObservedSevereMisses"].startswith("never report as zero risk"), "zero-event risk weakened")
    require(contract["evidenceRoles"]["priorZeroMaterialTailRules"].startswith("candidate-specific"), "candidate rule promoted")
    require(contract["preservedBoundaries"] == {
        "productionCATChanged": False,
        "canonicalEVAL001Changed": False,
        "canonicalRISK001Status": "deferred",
        "empiricalRiskCalibrationProductionEnabled": False,
        "nextSyntheticSafeguardAllowed": False,
        "developmentConfirmationAccessAllowed": False,
        "releaseHoldoutAccessAllowed": False,
    }, "preserved boundary changed")

    for anchor in (
        "Q_0.05(C | E) >= 0.98",
        "P_severe(c_severe) = Pr(C_realized < c_severe)",
        "ES_severe(c_severe) = E[L | C_realized < c_severe]",
        "not silently promoted to a release threshold",
        "`RISK-001` remains deferred",
    ):
        require(anchor in markdown, f"markdown contract missing anchor: {anchor}")

    candidate_hashes = verification["candidateArtifacts"]
    for path, key in (
        (SOURCE_LOCK, "sourceLockSHA256"),
        (DELTA, "deltaSHA256"),
        (LEDGER, "ledgerSHA256"),
        (CONTRACT, "contractJSONSHA256"),
        (MARKDOWN, "contractMarkdownSHA256"),
    ):
        require(sha256(path.read_bytes()) == candidate_hashes[key], f"verification hash mismatch: {key}")
    require(verification["deltaItems"] == {"implemented": 3, "total": 3}, "delta verification changed")
    require(
        verification["requirements"]
        == {"activePresent": 10, "activeTotal": 10, "deferredExplicit": 2, "deferredTotal": 2},
        "requirement verification changed",
    )
    require(verification["preservation"]["canonicalRequirementChanges"] == 0, "canonical changes hidden")
    require(verification["validation"]["independentForwardReview"] == "not-performed-no-subagent-authority", "independent status misstated")
    require(
        verification["disposition"]
        == "definitions-verified-independent-review-pending-release-values-blocked",
        "verification disposition changed",
    )
    require(revision_state["phase"] == "SEMANTIC_VERIFIED", "revision phase overclaimed")
    require(revision_state["validationResults"]["independent"] == "not-performed-no-subagent-authority", "revision independent status changed")
    require(len(revision_state["openFindings"]) == 2, "open findings changed")


def self_test(source_lock, delta, ledger, contract, markdown, verification, revision_state):
    validate(source_lock, delta, ledger, contract, markdown, verification, revision_state)
    mutations = []
    promoted_threshold = copy.deepcopy(contract)
    promoted_threshold["releaseDecisionFields"]["releaseSevereCoverageThreshold"] = 0.96
    mutations.append((source_lock, delta, ledger, promoted_threshold))
    enabled_risk = copy.deepcopy(contract)
    enabled_risk["preservedBoundaries"]["empiricalRiskCalibrationProductionEnabled"] = True
    mutations.append((source_lock, delta, ledger, enabled_risk))
    missing_requirement = copy.deepcopy(ledger)
    missing_requirement["requirements"].pop()
    mutations.append((source_lock, delta, missing_requirement, contract))
    for source_value, delta_value, ledger_value, contract_value in mutations:
        try:
            validate(
                source_value,
                delta_value,
                ledger_value,
                contract_value,
                markdown,
                verification,
                revision_state,
            )
        except ValidationError:
            continue
        raise AssertionError("invalid tail-risk contract unexpectedly passed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    source_lock = load(SOURCE_LOCK)
    delta = load(DELTA)
    ledger = load(LEDGER)
    contract = load(CONTRACT)
    markdown = MARKDOWN.read_text()
    verification = load(VERIFICATION)
    revision_state = load(REVISION_STATE)
    if args.self_test:
        self_test(
            source_lock,
            delta,
            ledger,
            contract,
            markdown,
            verification,
            revision_state,
        )
        print("vocabulary tail-risk acceptance contract self-test passed")
    else:
        validate(
            source_lock,
            delta,
            ledger,
            contract,
            markdown,
            verification,
            revision_state,
        )
        print("vocabulary tail-risk acceptance contract valid")


if __name__ == "__main__":
    main()
