#!/usr/bin/env python3
"""Validate the disabled calibration assignment proposal and reconstruct its fixture."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
POLICY_PATH = ROOT / "docs/plans/vocabulary-validation-evidence/calibration-assignment-policy-proposal-v1.json"
FIXTURE_PATH = ROOT / "docs/plans/vocabulary-validation-evidence/calibration-assignment-reconstruction-fixture-v1.json"


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def close(actual: float, expected: float, tolerance: float = 0.00001) -> bool:
    return math.isfinite(actual) and abs(actual - expected) <= tolerance


def pool_hash(strata: list[dict]) -> str:
    encoded = json.dumps(strata, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def theta_bin(policy: dict, theta: float) -> str:
    boundaries = policy["abilityBins"]["boundaries"]
    labels = policy["abilityBins"]["labels"]
    return labels[sum(theta >= boundary for boundary in boundaries)]


def is_tail_ordinal(policy: dict, ordinal: int) -> bool:
    first = policy["slotPolicy"]["tailValidationFirstOrdinal"]
    cadence = policy["slotPolicy"]["tailValidationCadence"]
    return ordinal >= first and (ordinal - first) % cadence == 0


def validate_policy(policy: dict) -> None:
    if policy.get("schemaVersion") != 1 or policy.get("proposalStatus") != "proposedNotApproved":
        raise ValueError("policy must remain a schema-v1 unapproved proposal")
    if policy.get("canonicalRequirementIDs") != ["CALDATA-001"]:
        raise ValueError("policy may propose a delta only for CALDATA-001")
    activation = policy.get("activation", {})
    if activation.get("enabled") is not False or activation.get("requiresSeparateApproval") is not True:
        raise ValueError("calibration assignment must remain disabled pending separate approval")
    for field in ("defaultSetting", "diagnosticFlag", "rehearsalFixture"):
        if activation.get(field) is not False:
            raise ValueError(f"activation.{field} must remain false")
    slot = policy["slotPolicy"]
    probability = slot["baseOpportunityProbability"]
    if isinstance(probability, bool) or not 0.05 <= probability <= 0.10:
        raise ValueError("base opportunity probability must remain within canonical 5-10%")
    if slot["rounding"] != "none" or slot["minimumAssignmentQuota"] != 0:
        raise ValueError("short sessions must not gain a forced calibration quota")
    if slot["questionLimitsRemain"] != [8, 20, 80] or slot["countsTowardQuestionLimit"] is not True:
        raise ValueError("existing question-limit semantics must remain explicit")
    if slot["calibrationNeverReplacesTailValidation"] is not True:
        raise ValueError("tail validation must retain priority")
    boundaries = policy["abilityBins"]["boundaries"]
    if boundaries != sorted(set(boundaries)) or len(policy["abilityBins"]["labels"]) != len(boundaries) + 1:
        raise ValueError("ability bins must be strictly ordered and completely labeled")
    if "one fifth" not in policy["abilityBins"]["underrepresentedDefinition"]:
        raise ValueError("underrepresented ability-bin support must be explicitly defined")
    predicted = policy["candidatePool"]["predictedKnownBoundaries"]
    if predicted[0] != 0 or predicted[-1] != 1 or predicted != sorted(set(predicted)):
        raise ValueError("predicted-known bins must partition [0, 1]")
    minimum = {"questionOrdinal", "selectionType", "predictedKnownBeforeAnswer", "thetaBinBeforeAnswer"}
    if set(policy["traceSchema"]["minimumCanonicalFields"]) != minimum:
        raise ValueError("minimum canonical trace fields changed")
    if policy["privacy"]["ordinaryProductExportUnchanged"] is not True or policy["privacy"]["automaticTransmission"] is not False:
        raise ValueError("ordinary export/privacy behavior changed")

    expected_by_questions = {}
    for scenario in policy["feasibility"]["questionScenarios"]:
        questions = scenario["scoredQuestions"]
        tail = sum(is_tail_ordinal(policy, ordinal) for ordinal in range(1, questions + 1))
        eligible = questions - tail
        expected = eligible * probability
        if scenario["reservedTailOrdinals"] != tail or scenario["eligibleOpportunities"] != eligible:
            raise ValueError("feasibility tail/eligible counts are inconsistent")
        if not close(scenario["expectedAssignments"], expected) or not close(scenario["expectedShareOfScoredQuestions"], expected / questions):
            raise ValueError("feasibility expected assignment calculation is inconsistent")
        expected_by_questions[questions] = expected
    assumptions = policy["feasibility"]["assumptions"]
    for projection in policy["feasibility"]["fixtureInventoryProjections"]:
        expected = expected_by_questions[projection["scoredQuestions"]]
        items = projection["uniqueItems"]
        sessions100 = assumptions["independentLearnersRequiredPerItem"] * items / expected
        sessions30cells = assumptions["exploratoryLearnersRequiredPerAbilityCell"] * assumptions["abilityBinCount"] * items / expected
        if not close(projection["sessionsFor100LearnersPerItem"], sessions100, 0.01):
            raise ValueError("100-learner feasibility projection is inconsistent")
        if not close(projection["sessionsFor30LearnersPerItemAbilityCell"], sessions30cells, 0.01):
            raise ValueError("ability-cell feasibility projection is inconsistent")


def reconstruct(policy: dict, fixture: dict) -> list[dict]:
    if fixture.get("schemaVersion") != 1 or fixture.get("policyVersion") != policy["policyVersion"]:
        raise ValueError("fixture policy/schema version mismatch")
    rate = policy["slotPolicy"]["baseOpportunityProbability"]
    declared_order = policy["candidatePool"]["predictedKnownBinLabels"]
    reconstructed = []
    for opportunity in fixture["opportunities"]:
        ordinal = opportunity["questionOrdinal"]
        trace = opportunity["exportedTrace"]
        missing_trace = set(policy["traceSchema"]["minimumCanonicalFields"]) - set(trace)
        if missing_trace:
            raise ValueError(f"ordinal {ordinal}: missing canonical trace fields {sorted(missing_trace)}")
        predicted_before = trace["predictedKnownBeforeAnswer"]
        if isinstance(predicted_before, bool) or not isinstance(predicted_before, (int, float)) or not 0 <= predicted_before <= 1:
            raise ValueError(f"ordinal {ordinal}: invalid pre-answer prediction")
        actual_hash = pool_hash(opportunity["strata"])
        if opportunity["candidatePoolSHA256"] != actual_hash or trace["candidatePoolSHA256"] != actual_hash:
            raise ValueError(f"ordinal {ordinal}: candidate pool hash mismatch")
        eligible_count = sum(len(stratum["candidateIDs"]) for stratum in opportunity["strata"])
        if trace["eligibleCandidateCount"] != eligible_count:
            raise ValueError(f"ordinal {ordinal}: eligible candidate count mismatch")
        if trace["thetaBinBeforeAnswer"] != theta_bin(policy, opportunity["posteriorMeanBeforeQuestion"]):
            raise ValueError(f"ordinal {ordinal}: theta bin mismatch")
        if trace["assignmentPolicyVersion"] != policy["policyVersion"]:
            raise ValueError(f"ordinal {ordinal}: assignment policy version mismatch")
        if trace["supportSnapshotVersion"] != fixture["supportSnapshotVersion"] or trace["supportSnapshotSHA256"] != fixture["supportSnapshotSHA256"]:
            raise ValueError(f"ordinal {ordinal}: support snapshot mismatch")
        if trace["rngStreamID"] != fixture["rngStreamID"] or trace["slotDrawIndex"] != opportunity["slotDrawIndex"] or trace["slotDrawUniform"] != opportunity["slotDrawUniform"]:
            raise ValueError(f"ordinal {ordinal}: slot RNG provenance mismatch")

        if is_tail_ordinal(policy, ordinal):
            expected = {"outcome": "tailValidationReserved", "selectionType": "tailValidation", "jointProbability": 0.0}
            if trace["assignmentOutcome"] != expected["outcome"] or trace["selectionType"] != expected["selectionType"] or trace["assignmentOpportunityProbability"] != 0:
                raise ValueError(f"ordinal {ordinal}: tail validation was not preserved")
            reconstructed.append(expected)
            continue
        if eligible_count == 0:
            if trace["assignmentOutcome"] != "noEligibleCandidates":
                raise ValueError(f"ordinal {ordinal}: exhausted pool outcome mismatch")
            reconstructed.append({"outcome": "noEligibleCandidates", "jointProbability": 0.0})
            continue
        if not close(trace["assignmentOpportunityProbability"], rate):
            raise ValueError(f"ordinal {ordinal}: slot probability mismatch")
        if opportunity["slotDrawUniform"] >= rate:
            if trace["assignmentOutcome"] != "regularSelection" or trace["selectionType"] == "calibration":
                raise ValueError(f"ordinal {ordinal}: regular-selection outcome mismatch")
            reconstructed.append({"outcome": "regularSelection", "jointProbability": 0.0})
            continue

        nonempty = [stratum for stratum in opportunity["strata"] if stratum["candidateIDs"]]
        minimum_support = min(stratum["supportCount"] for stratum in nonempty)
        chosen = min(
            (stratum for stratum in nonempty if stratum["supportCount"] == minimum_support),
            key=lambda stratum: declared_order.index(stratum["predictedKnownBin"]),
        )
        item_draw = opportunity["itemDrawUniform"]
        if item_draw is None or not 0 <= item_draw < 1:
            raise ValueError(f"ordinal {ordinal}: assigned opportunity lacks item draw")
        item_index = min(int(item_draw * len(chosen["candidateIDs"])), len(chosen["candidateIDs"]) - 1)
        selected = chosen["candidateIDs"][item_index]
        item_probability = 1 / len(chosen["candidateIDs"])
        joint = rate * item_probability
        expected_fields = {
            "assignmentOutcome": "assigned",
            "selectionType": "calibration",
            "chosenPredictedKnownBin": chosen["predictedKnownBin"],
            "chosenStratumCandidateCount": len(chosen["candidateIDs"]),
            "selectedLexicalItemID": selected,
        }
        for field, expected in expected_fields.items():
            if trace.get(field) != expected:
                raise ValueError(f"ordinal {ordinal}: {field} is not reconstructible")
        if not close(trace["candidateSelectionProbability"], item_probability) or not close(trace["jointAssignmentProbability"], joint):
            raise ValueError(f"ordinal {ordinal}: assignment propensity mismatch")
        if trace["itemDrawIndex"] != opportunity["itemDrawIndex"] or trace["itemDrawUniform"] != item_draw:
            raise ValueError(f"ordinal {ordinal}: item RNG provenance mismatch")
        reconstructed.append({"outcome": "assigned", "selectedLexicalItemID": selected, "jointProbability": joint})
    return reconstructed


def self_test() -> None:
    policy = load(POLICY_PATH)
    fixture = load(FIXTURE_PATH)
    validate_policy(policy)
    reconstructed = reconstruct(policy, fixture)
    assert [row["outcome"] for row in reconstructed] == ["assigned", "tailValidationReserved", "regularSelection", "assigned"]

    enabled = copy.deepcopy(policy)
    enabled["activation"]["diagnosticFlag"] = True
    try:
        validate_policy(enabled)
        raise AssertionError("diagnostic flag activated calibration slots")
    except ValueError as error:
        assert "diagnosticFlag" in str(error)

    forced = copy.deepcopy(policy)
    forced["slotPolicy"]["minimumAssignmentQuota"] = 1
    try:
        validate_policy(forced)
        raise AssertionError("forced short-session quota was accepted")
    except ValueError as error:
        assert "forced calibration quota" in str(error)

    tampered = copy.deepcopy(fixture)
    tampered["opportunities"][0]["exportedTrace"]["jointAssignmentProbability"] = 0.075
    try:
        reconstruct(policy, tampered)
        raise AssertionError("incorrect joint propensity was accepted")
    except ValueError as error:
        assert "propensity" in str(error)
    print("vocabulary calibration assignment package self-test passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("policy", nargs="?", type=Path)
    parser.add_argument("fixture", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.policy is None or args.fixture is None:
        parser.error("provide policy and reconstruction fixture, or use --self-test")
    policy = load(args.policy)
    fixture = load(args.fixture)
    validate_policy(policy)
    reconstructed = reconstruct(policy, fixture)
    print(json.dumps({"policyVersion": policy["policyVersion"], "activationEnabled": False, "reconstructed": reconstructed}, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
