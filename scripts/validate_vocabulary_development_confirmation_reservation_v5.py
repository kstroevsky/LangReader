#!/usr/bin/env python3
"""Validate the sealed, unexecuted graceful-degradation confirmation reservation."""

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
MANIFEST = ARCHIVE / "development-confirmation-reservation-v5.json"
HISTORICAL_MANIFESTS = {
    "development-confirmation-v1": ARCHIVE / "development-confirmation-reservation-v1.json",
    "development-confirmation-v2": ARCHIVE / "development-confirmation-reservation-v2.json",
    "development-confirmation-v3": ARCHIVE / "development-confirmation-reservation-v3.json",
    "development-confirmation-v4": ARCHIVE / "development-confirmation-reservation-v4.json",
}
HISTORICAL_SHA256 = {
    "development-confirmation-v1": "a43e45a5fef43367b20e36e0f41684186901af325e2e597a994857591015303a",
    "development-confirmation-v2": "19ccb4a9bddff02df1c074c85b56ffc782e7216d1a883a60cc088ac7338af89d",
    "development-confirmation-v3": "8c25324b82cf54e7d1945ce2918c61d4eecae8522743839323e24edb58f7fb4c",
    "development-confirmation-v4": "4717a4b2b7f2b0e55d03321a5754a52ceb31c2e7b8ac232e67464fe8a89c9006",
}
SOURCE_LOCK = ROOT / "docs/plans/vocabulary-validation-boundary/implementation-evidence/graceful-degradation-generator-source-lock-v5.json"
SOURCE_REVISION = "294294187d55d45a33eef32db11fb7f8bdb289d0"
RESERVATION_SHA256 = "ace9fa7c0e44df40f7eff8c6572828296d4acfd09c857211c207989af6f73647"
SOURCE_LOCK_SHA256 = "749764b5ae59a3bb1e741777602a772dedf1327eaa10710f0cac1afb745dc50e"
DEVELOPMENT_CHECK = ARCHIVE / "german-nlp-graceful-degradation-check-2026-09-22.json"
DEVELOPMENT_CHECK_SHA256 = "06d2059beb945d9c23c61c21872de61e939f7b7d81a8ef251d690efb9e1e375c"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def derived_run(root: bytes, ordinal: int) -> tuple[bytes, int, str]:
    digest = hashlib.sha256(root + f"development-confirmation-v5/run/{ordinal}".encode()).digest()
    return digest, int.from_bytes(digest[:8], "big") or 1, digest.hex()[:16]


def derived_document_id(run_digest: bytes, ordinal: int) -> str:
    return hashlib.sha256(run_digest + f"/document/{ordinal}".encode()).hexdigest()[:24]


def validate_source_lock(
    lock: dict,
    *,
    historical_inputs: dict | None = None,
) -> None:
    if lock.get("schemaVersion") != 1 \
            or lock.get("lockRole") != "graceful-degradation-generator-provenance-v5":
        raise ValueError("unsupported v5 generator source lock")
    if lock.get("sourceRevision") != SOURCE_REVISION:
        raise ValueError("v5 generator revision changed")
    if lock.get("generatorInputsCleanAtLock") is not True or lock.get("candidateFrozen") is not False:
        raise ValueError("v5 lock has invalid clean-input/candidate status")
    if lock.get("swiftMode") != "Swift 6" \
            or lock.get("standaloneSwiftFlags") != ["-swift-version", "6", "-warnings-as-errors", "-O"]:
        raise ValueError("v5 Swift build contract changed")

    historical = historical_inputs if historical_inputs is not None else v2.historical_source_lock(SOURCE_REVISION)
    if lock.get("generatorInputs") != historical:
        raise ValueError("v5 source lock does not match its generator commit")

    analysis = lock.get("analysisBinding", {})
    if analysis.get("status") != "provenanceOnlyNotFrozen" \
            or analysis.get("candidateAnalysisAndDecisionRulesChecksum") is not None:
        raise ValueError("v5 lock incorrectly claims an analysis freeze")
    if analysis.get("paths") != [
        "scripts/validate_vocabulary_assessment_report.py",
        "scripts/summarize_vocabulary_assessment_benchmarks.py",
        "scripts/compare_vocabulary_stopping_reports.py",
        "docs/plans/vocabulary-measurement-coherence/target-ledger.json",
    ]:
        raise ValueError("v5 analysis provenance paths changed")
    if lock.get("germanNLPGracefulDegradationCheckSHA256") != DEVELOPMENT_CHECK_SHA256 \
            or sha256(DEVELOPMENT_CHECK.read_bytes()) != DEVELOPMENT_CHECK_SHA256:
        raise ValueError("v5 graceful-degradation evidence changed")
    if lock.get("protectedOutcomesAccessed") is not False:
        raise ValueError("v5 lock cannot claim protected outcome access")


def validate(manifest: dict, *, verify_files: bool = True) -> dict:
    if manifest.get("schemaVersion") != 5 or manifest.get("reservationID") != "development-confirmation-v5":
        raise ValueError("unsupported v5 development-confirmation reservation")
    if manifest.get("dataRole") != "development-confirmation" \
            or manifest.get("executionStatus") != "reservedNotExecuted":
        raise ValueError("v5 reservation role/status changed")
    if manifest.get("reservationSourceRevision") != SOURCE_REVISION \
            or manifest.get("supersedesAsActiveReservation") != "development-confirmation-v4":
        raise ValueError("v5 source revision or active-reservation transition changed")
    if manifest.get("historicalReservationStatuses") != {
        "development-confirmation-v1": "reservedNotExecuted",
        "development-confirmation-v2": "reservedNotExecuted",
        "development-confirmation-v3": "reservedNotExecuted",
        "development-confirmation-v4": "reservedNotExecuted",
    }:
        raise ValueError("v5 historical reservation statuses changed")

    derivation = manifest.get("seedDerivation", {})
    root = derivation.get("seedDerivationRoot", "")
    if not isinstance(root, str) or not re.fullmatch(r"[0-9a-f]{64}", root):
        raise ValueError("v5 seed root must be 32 lowercase-hex bytes")
    if derivation.get("algorithm") != "SHA256(rootBytes || UTF8('development-confirmation-v5/run/' || zeroBasedRunOrdinal)); seed=first8BytesUInt64BE, zero maps to one" \
            or derivation.get("documentIdentityAlgorithm") != "first24Hex(SHA256(fullRunDigest || UTF8('/document/' || zeroBasedDocumentOrdinal)))":
        raise ValueError("v5 identity derivation changed")

    workload = manifest.get("workload", {})
    if workload.get("readersPerScenario") != 64 or workload.get("documentsPerScenario") != 8 \
            or workload.get("lemmasPerDocument") != 400 \
            or workload.get("scenarios") != ["well-specified", "item-residual", "response-noise", "idiosyncratic-knowledge"] \
            or workload.get("modes") != ["all-unknown", "coverage-98"] \
            or workload.get("warmAndCold") is not True:
        raise ValueError("v5 workload changed")

    runs = manifest.get("runs")
    if not isinstance(runs, list) or len(runs) != 3:
        raise ValueError("v5 must contain exactly three runs")
    seeds: set[int] = set()
    documents: set[str] = set()
    for ordinal, run in enumerate(runs):
        digest, seed, run_id = derived_run(bytes.fromhex(root), ordinal)
        expected_documents = [derived_document_id(digest, index) for index in range(8)]
        if run.get("runOrdinal") != ordinal or run.get("runID") != run_id or run.get("seed") != seed:
            raise ValueError(f"v5 run {ordinal} identity changed")
        if run.get("opaqueDocumentDerivationIDs") != expected_documents:
            raise ValueError(f"v5 run {ordinal} document identities changed")
        seeds.add(seed)
        documents.update(expected_documents)
    if len(seeds) != 3 or len(documents) != 24:
        raise ValueError("duplicate v5 identity")

    for name, path in HISTORICAL_MANIFESTS.items():
        if sha256(path.read_bytes()) != HISTORICAL_SHA256[name]:
            raise ValueError(f"historical reservation bytes changed: {name}")
        historical = read_json(path)
        if historical.get("executionStatus") != "reservedNotExecuted" \
                or historical.get("freezeAndConsumption", {}).get("outcomesInspected") is not False:
            raise ValueError(f"historical reservation is no longer sealed and unexecuted: {name}")

    non_overlap = manifest.get("nonOverlap", {})
    if non_overlap.get("identityCorpusRevision") != SOURCE_REVISION \
            or non_overlap.get("identityCorpusRoots") != list(v2.PRIOR_EVIDENCE_ROOTS) \
            or non_overlap.get("historicalReservationSHA256") != HISTORICAL_SHA256 \
            or non_overlap.get("allReservedSeedsMustBeDisjoint") is not True \
            or non_overlap.get("allOpaqueDocumentDerivationIDsMustBeUnique") is not True \
            or "v1-v4" not in str(non_overlap.get("opaqueDocumentNamespaceNote", "")):
        raise ValueError("v5 non-overlap contract changed")
    prior_seeds, prior_documents, file_count = v2.prior_artifact_identities(
        SOURCE_REVISION,
        MANIFEST.relative_to(ROOT).as_posix(),
    )
    if file_count < 100 or not {1, 2, 7, 17, 20260909, 20260912, 20260913, 20260914}.issubset(prior_seeds):
        raise ValueError("v5 prior identity corpus is incomplete")
    v2.require_disjoint(seeds, documents, prior_seeds, prior_documents)

    generator = manifest.get("generatorLock", {})
    if generator.get("path") != SOURCE_LOCK.relative_to(ROOT).as_posix() \
            or generator.get("sha256") != SOURCE_LOCK_SHA256:
        raise ValueError("v5 generator lock binding changed")
    if verify_files:
        lock_bytes = SOURCE_LOCK.read_bytes()
        if sha256(lock_bytes) != SOURCE_LOCK_SHA256:
            raise ValueError("v5 generator lock bytes changed")
        validate_source_lock(json.loads(lock_bytes))

    freeze = manifest.get("freezeAndConsumption", {})
    if any(freeze.get(key) is not None for key in (
        "candidateFreeze", "analysisFreeze", "decisionRulesChecksum", "consumedByCandidateCycle",
    )):
        raise ValueError("v5 prematurely claims a candidate/analysis freeze or consumption")
    if freeze.get("outcomeArtifacts") != [] or freeze.get("outcomesInspected") is not False \
            or freeze.get("releaseHoldoutAccessAllowed") is not False:
        raise ValueError("v5 contains or authorizes protected outcomes")
    if freeze.get("requiredBeforeExecution") != [
        "candidate commit and clean-tree hash",
        "model/configuration/resource hashes",
        "analysis and decision-rule checksum",
        "reviewed decision to consume this specific reservation",
    ]:
        raise ValueError("v5 execution prerequisites changed")
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
    for name, path in HISTORICAL_MANIFESTS.items():
        historical = read_json(path)
        historical_seeds = {run["seed"] for run in historical["runs"]}
        historical_documents = {
            document
            for run in historical["runs"]
            for document in run["opaqueDocumentDerivationIDs"]
        }
        if not historical_seeds.issubset(prior_seeds) \
                or not historical_documents.issubset(prior_documents):
            raise AssertionError(f"v5 prior identity corpus omitted {name} identities")

    first_seed = original["runs"][0]["seed"]
    first_document = original["runs"][0]["opaqueDocumentDerivationIDs"][0]
    for seed_set, document_set in (
        (prior_seeds | {first_seed}, prior_documents),
        (prior_seeds, prior_documents | {first_document}),
    ):
        try:
            v2.require_disjoint({first_seed}, {first_document}, seed_set, document_set)
        except ValueError:
            pass
        else:
            raise AssertionError("accepted a synthetic v5 prior-identity collision")

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
        raise AssertionError(f"accepted changed v5 {label}")

    lock = read_json(SOURCE_LOCK)
    changed_historical = copy.deepcopy(v2.historical_source_lock(SOURCE_REVISION))
    changed_historical["files"]["Package.swift"] = "0" * 64
    try:
        validate_source_lock(lock, historical_inputs=changed_historical)
    except ValueError:
        pass
    else:
        raise AssertionError("accepted mismatched historical v5 generator inputs")

    real_read_bytes = Path.read_bytes

    def missing_lock(path: Path) -> bytes:
        if path == SOURCE_LOCK:
            raise FileNotFoundError("synthetic missing v5 source lock")
        return real_read_bytes(path)

    with patch.object(Path, "read_bytes", missing_lock):
        try:
            validate(original)
        except FileNotFoundError:
            pass
        else:
            raise AssertionError("accepted missing v5 source lock")
    print("graceful-degradation development-confirmation reservation v5 self-test passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if sha256(MANIFEST.read_bytes()) != RESERVATION_SHA256:
        raise ValueError("v5 reservation is missing or differs from its frozen checksum")
    if args.self_test:
        self_test()
    else:
        print(json.dumps(validate(read_json(MANIFEST)), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
