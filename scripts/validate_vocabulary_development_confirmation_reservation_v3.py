#!/usr/bin/env python3
"""Validate the sealed, unexecuted post-cleanup confirmation reservation."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
from pathlib import Path
from unittest.mock import patch

import validate_vocabulary_development_confirmation_reservation_v2 as v2


ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "docs/plans/vocabulary-validation-evidence"
MANIFEST = ARCHIVE / "development-confirmation-reservation-v3.json"
V1_MANIFEST = ARCHIVE / "development-confirmation-reservation-v1.json"
V2_MANIFEST = ARCHIVE / "development-confirmation-reservation-v2.json"
SOURCE_LOCK = ROOT / "docs/plans/vocabulary-validation-boundary/implementation-evidence/post-cleanup-generator-source-lock-v3.json"
SOURCE_REVISION = "0dc16efd21e2816a5154b4d515c2b5272e6b8fe3"
V1_SHA256 = "a43e45a5fef43367b20e36e0f41684186901af325e2e597a994857591015303a"
V2_SHA256 = "19ccb4a9bddff02df1c074c85b56ffc782e7216d1a883a60cc088ac7338af89d"
RESERVATION_SHA256 = "8c25324b82cf54e7d1945ce2918c61d4eecae8522743839323e24edb58f7fb4c"
SOURCE_LOCK_SHA256 = "b11db3185cfb70c22115da15f82e554c1dda3e5553112a06c0bc95257975574a"
PARITY_REPORT = ROOT / "docs/plans/vocabulary-validation-boundary/implementation-evidence/parity-followup-2026-09-21.json"
FOLLOWUP_PLAN = ROOT / "docs/plans/vocabulary-validation-boundary/revision-2026-09-21-boundary-followup/candidate-plan.md"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def derived_run(root: bytes, ordinal: int) -> tuple[bytes, int, str]:
    digest = hashlib.sha256(root + f"development-confirmation-v3/run/{ordinal}".encode()).digest()
    return digest, int.from_bytes(digest[:8], "big") or 1, digest.hex()[:16]


def derived_document_id(run_digest: bytes, ordinal: int) -> str:
    return hashlib.sha256(run_digest + f"/document/{ordinal}".encode()).hexdigest()[:24]


def validate_source_lock(
    lock: dict,
    *,
    current_inputs: dict | None = None,
    historical_inputs: dict | None = None,
) -> None:
    if lock.get("schemaVersion") != 1 or lock.get("lockRole") != "post-cleanup-generator-provenance-v3":
        raise ValueError("unsupported v3 generator source lock")
    if lock.get("sourceRevision") != SOURCE_REVISION:
        raise ValueError("v3 generator revision changed")
    if lock.get("generatorInputsCleanAtLock") is not True or lock.get("candidateFrozen") is not False:
        raise ValueError("v3 lock has invalid clean-input/candidate status")
    if lock.get("swiftMode") != "Swift 6" \
            or lock.get("standaloneSwiftFlags") != ["-swift-version", "6", "-warnings-as-errors", "-O"]:
        raise ValueError("v3 Swift build contract changed")
    current = current_inputs if current_inputs is not None else v2.current_source_lock()
    historical = historical_inputs if historical_inputs is not None else v2.historical_source_lock(SOURCE_REVISION)
    if lock.get("generatorInputs") != historical:
        raise ValueError("v3 source lock does not match its generator commit")
    if lock.get("generatorInputs") != current:
        raise ValueError("current generator inputs no longer match active v3 reservation")
    analysis = lock.get("analysisBinding", {})
    if analysis.get("status") != "provenanceOnlyNotFrozen" \
            or analysis.get("candidateAnalysisAndDecisionRulesChecksum") is not None:
        raise ValueError("v3 lock incorrectly claims an analysis freeze")
    if analysis.get("paths") != [
        "scripts/validate_vocabulary_assessment_report.py",
        "scripts/summarize_vocabulary_assessment_benchmarks.py",
        "scripts/compare_vocabulary_stopping_reports.py",
        "docs/plans/vocabulary-measurement-coherence/target-ledger.json",
    ]:
        raise ValueError("v3 analysis provenance paths changed")
    if lock.get("acceptedFollowupPlanSHA256") != sha256(FOLLOWUP_PLAN.read_bytes()):
        raise ValueError("accepted follow-up plan binding changed")
    if lock.get("baselineParityManifestSHA256") != sha256(v2.PARITY_MANIFEST.read_bytes()) \
            or lock.get("postCleanupParityReportSHA256") != sha256(PARITY_REPORT.read_bytes()):
        raise ValueError("v3 parity evidence changed")
    if lock.get("protectedOutcomesAccessed") is not False:
        raise ValueError("v3 lock cannot claim protected outcome access")


def validate(manifest: dict, *, verify_files: bool = True) -> dict:
    if manifest.get("schemaVersion") != 3 or manifest.get("reservationID") != "development-confirmation-v3":
        raise ValueError("unsupported v3 development-confirmation reservation")
    if manifest.get("dataRole") != "development-confirmation" \
            or manifest.get("executionStatus") != "reservedNotExecuted":
        raise ValueError("v3 reservation role/status changed")
    if manifest.get("reservationSourceRevision") != SOURCE_REVISION \
            or manifest.get("supersedesAsActiveReservation") != "development-confirmation-v2":
        raise ValueError("v3 source revision or active-reservation transition changed")
    if manifest.get("historicalReservationStatuses") != {
        "development-confirmation-v1": "reservedNotExecuted",
        "development-confirmation-v2": "reservedNotExecuted",
    }:
        raise ValueError("historical reservation statuses changed")

    derivation = manifest.get("seedDerivation", {})
    root = derivation.get("seedDerivationRoot", "")
    if not isinstance(root, str) or not re.fullmatch(r"[0-9a-f]{64}", root):
        raise ValueError("v3 seed root must be 32 lowercase-hex bytes")
    if derivation.get("algorithm") != "SHA256(rootBytes || UTF8('development-confirmation-v3/run/' || zeroBasedRunOrdinal)); seed=first8BytesUInt64BE, zero maps to one" \
            or derivation.get("documentIdentityAlgorithm") != "first24Hex(SHA256(fullRunDigest || UTF8('/document/' || zeroBasedDocumentOrdinal)))":
        raise ValueError("v3 identity derivation changed")
    workload = manifest.get("workload", {})
    if workload.get("readersPerScenario") != 64 or workload.get("documentsPerScenario") != 8 \
            or workload.get("lemmasPerDocument") != 400 \
            or workload.get("scenarios") != ["well-specified", "item-residual", "response-noise", "idiosyncratic-knowledge"] \
            or workload.get("modes") != ["all-unknown", "coverage-98"] \
            or workload.get("warmAndCold") is not True:
        raise ValueError("v3 workload changed")

    runs = manifest.get("runs")
    if not isinstance(runs, list) or len(runs) != 3:
        raise ValueError("v3 must contain exactly three runs")
    seeds: set[int] = set()
    documents: set[str] = set()
    for ordinal, run in enumerate(runs):
        digest, seed, run_id = derived_run(bytes.fromhex(root), ordinal)
        expected_documents = [derived_document_id(digest, index) for index in range(8)]
        if run.get("runOrdinal") != ordinal or run.get("runID") != run_id or run.get("seed") != seed:
            raise ValueError(f"v3 run {ordinal} identity changed")
        if run.get("opaqueDocumentDerivationIDs") != expected_documents:
            raise ValueError(f"v3 run {ordinal} document identities changed")
        seeds.add(seed)
        documents.update(expected_documents)
    if len(seeds) != 3 or len(documents) != 24:
        raise ValueError("duplicate v3 identity")

    if sha256(V1_MANIFEST.read_bytes()) != V1_SHA256 or sha256(V2_MANIFEST.read_bytes()) != V2_SHA256:
        raise ValueError("historical reservation bytes changed")
    for path in (V1_MANIFEST, V2_MANIFEST):
        historical = read_json(path)
        if historical.get("executionStatus") != "reservedNotExecuted" \
                or historical.get("freezeAndConsumption", {}).get("outcomesInspected") is not False:
            raise ValueError("historical reservation is no longer sealed and unexecuted")

    non_overlap = manifest.get("nonOverlap", {})
    if non_overlap.get("identityCorpusRevision") != SOURCE_REVISION \
            or non_overlap.get("identityCorpusRoots") != list(v2.PRIOR_EVIDENCE_ROOTS) \
            or non_overlap.get("historicalReservationSHA256") != {
                "development-confirmation-v1": V1_SHA256,
                "development-confirmation-v2": V2_SHA256,
            } \
            or non_overlap.get("allReservedSeedsMustBeDisjoint") is not True \
            or non_overlap.get("allOpaqueDocumentDerivationIDsMustBeUnique") is not True \
            or "24-hex" not in str(non_overlap.get("opaqueDocumentNamespaceNote", "")):
        raise ValueError("v3 non-overlap contract changed")
    prior_seeds, prior_documents, file_count = v2.prior_artifact_identities(
        SOURCE_REVISION,
        MANIFEST.relative_to(ROOT).as_posix(),
    )
    if file_count < 100 or not {1, 2, 7, 17, 20260909, 20260912, 20260913, 20260914}.issubset(prior_seeds):
        raise ValueError("v3 prior identity corpus is incomplete")
    v2.require_disjoint(seeds, documents, prior_seeds, prior_documents)

    generator = manifest.get("generatorLock", {})
    if generator.get("path") != SOURCE_LOCK.relative_to(ROOT).as_posix() \
            or generator.get("sha256") != SOURCE_LOCK_SHA256:
        raise ValueError("v3 generator lock binding changed")
    if verify_files:
        lock_bytes = SOURCE_LOCK.read_bytes()
        if sha256(lock_bytes) != SOURCE_LOCK_SHA256:
            raise ValueError("v3 generator lock bytes changed")
        validate_source_lock(json.loads(lock_bytes))

    freeze = manifest.get("freezeAndConsumption", {})
    if any(freeze.get(key) is not None for key in (
        "candidateFreeze", "analysisFreeze", "decisionRulesChecksum", "consumedByCandidateCycle",
    )):
        raise ValueError("v3 prematurely claims a candidate/analysis freeze or consumption")
    if freeze.get("outcomeArtifacts") != [] or freeze.get("outcomesInspected") is not False \
            or freeze.get("releaseHoldoutAccessAllowed") is not False:
        raise ValueError("v3 contains or authorizes protected outcomes")
    if freeze.get("requiredBeforeExecution") != [
        "candidate commit and clean-tree hash",
        "model/configuration/resource hashes",
        "analysis and decision-rule checksum",
        "reviewed decision to consume this specific reservation",
    ]:
        raise ValueError("v3 execution prerequisites changed")
    return {
        "reservationID": manifest["reservationID"],
        "executionStatus": "reservedNotExecuted",
        "runs": 3,
        "documents": 24,
        "priorIdentityFiles": file_count,
    }


def self_test() -> None:
    original = read_json(MANIFEST)
    validate(original)
    prior_seeds, prior_documents, _ = v2.prior_artifact_identities(
        SOURCE_REVISION,
        MANIFEST.relative_to(ROOT).as_posix(),
    )
    v2_manifest = read_json(V2_MANIFEST)
    v2_seeds = {run["seed"] for run in v2_manifest["runs"]}
    v2_documents = {
        document
        for run in v2_manifest["runs"]
        for document in run["opaqueDocumentDerivationIDs"]
    }
    if not v2_seeds.issubset(prior_seeds) or not v2_documents.issubset(prior_documents):
        raise AssertionError("v3 prior identity corpus omitted v2 identities")
    try:
        v2.require_disjoint(
            {next(iter(v2_seeds))},
            {next(iter(v2_documents))},
            prior_seeds,
            prior_documents,
        )
    except ValueError:
        pass
    else:
        raise AssertionError("accepted explicit v2-to-v3 identity collision")
    mutations = (
        ("seed", lambda value: value["runs"][0].__setitem__("seed", 1)),
        ("document", lambda value: value["runs"][0]["opaqueDocumentDerivationIDs"].__setitem__(0, "0" * 24)),
        ("outcome", lambda value: value["freezeAndConsumption"]["outcomeArtifacts"].append("result.json")),
        ("candidate freeze", lambda value: value["freezeAndConsumption"].__setitem__("candidateFreeze", {})),
        ("lock", lambda value: value["generatorLock"].__setitem__("sha256", "0" * 64)),
    )
    for label, mutate in mutations:
        changed = copy.deepcopy(original)
        mutate(changed)
        try:
            validate(changed)
        except ValueError:
            continue
        raise AssertionError(f"accepted changed v3 {label}")

    lock = read_json(SOURCE_LOCK)
    changed_inputs = copy.deepcopy(v2.current_source_lock())
    changed_inputs["files"]["Package.swift"] = "0" * 64
    try:
        validate_source_lock(lock, current_inputs=changed_inputs)
    except ValueError:
        pass
    else:
        raise AssertionError("accepted mismatched current generator inputs")

    real_read_bytes = Path.read_bytes

    def missing_lock(path: Path) -> bytes:
        if path == SOURCE_LOCK:
            raise FileNotFoundError("synthetic missing v3 source lock")
        return real_read_bytes(path)

    with patch.object(Path, "read_bytes", missing_lock):
        try:
            validate(original)
        except FileNotFoundError:
            pass
        else:
            raise AssertionError("accepted missing v3 source lock")
    print("post-cleanup development-confirmation reservation v3 self-test passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if sha256(MANIFEST.read_bytes()) != RESERVATION_SHA256:
        raise ValueError("v3 reservation is missing or differs from its frozen checksum")
    if args.self_test:
        self_test()
    else:
        print(json.dumps(validate(read_json(MANIFEST)), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
