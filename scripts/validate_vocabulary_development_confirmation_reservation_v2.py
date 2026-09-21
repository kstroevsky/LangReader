#!/usr/bin/env python3
"""Check the unexecuted post-extraction confirmation reservation and source lock."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import subprocess
from functools import cache
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "docs/plans/vocabulary-validation-evidence"
MANIFEST = ARCHIVE / "development-confirmation-reservation-v2.json"
HISTORICAL_MANIFEST = ARCHIVE / "development-confirmation-reservation-v1.json"
SOURCE_LOCK = ROOT / "docs/plans/vocabulary-validation-boundary/implementation-evidence/extracted-generator-source-lock.json"
HISTORICAL_SHA256 = "a43e45a5fef43367b20e36e0f41684186901af325e2e597a994857591015303a"
# Filled only after the new reservation has been written and reviewed. This
# checksum makes its identities immutable even though its validator can evolve.
RESERVATION_SHA256 = "19ccb4a9bddff02df1c074c85b56ffc782e7216d1a883a60cc088ac7338af89d"
SOURCE_TREES = ("Sources/LeafReaderCore", "Sources/LeafReaderValidation")
LOCKED_FILES = (
    "Package.swift",
    "scripts/build_core_module.sh",
    "scripts/build_validation_module.sh",
    "scripts/evaluate_vocabulary_assessment.sh",
    "scripts/evaluate_vocabulary_assessment.swift",
    "scripts/evaluate_vocabulary_pos_fixtures.sh",
    "scripts/evaluate_vocabulary_pos_fixtures.swift",
    "scripts/validate_vocabulary_assessment_report.py",
    "scripts/summarize_vocabulary_assessment_benchmarks.py",
    "scripts/compare_vocabulary_stopping_reports.py",
    "docs/plans/vocabulary-measurement-coherence/target-ledger.json",
)
KNOWN_DEVELOPMENT_SEEDS = (20260815, 20260908)
FROZEN_RELEASE_SEEDS = (13785352245285352300, 16855471854424563266, 5886616191894718396)
PARITY_MANIFEST = ROOT / "docs/plans/vocabulary-validation-boundary/implementation-evidence/extraction-parity-manifest.json"
PARITY_REPORT = ROOT / "docs/plans/vocabulary-validation-boundary/implementation-evidence/parity-4.json"
# This Git tree is the versioned inventory of development/release artifacts
# that existed when v2 was sealed. Do not replace it with a moving HEAD scan.
PRIOR_EVIDENCE_REVISION = "5de7128feb8bc2cab2457d88d0fd7d88671654d9"
PRIOR_EVIDENCE_ROOTS = ("docs/perf", "docs/plans", "scripts/fixtures")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def source_tree_fingerprint(relative_dir: str) -> tuple[int, str]:
    directory = ROOT / relative_dir
    if not directory.is_dir():
        raise ValueError(f"source tree missing: {relative_dir}")
    paths = sorted(path for path in directory.rglob("*") if path.is_file())
    if not paths:
        raise ValueError(f"source tree empty: {relative_dir}")
    digest = hashlib.sha256()
    for path in paths:
        relative_path = path.relative_to(ROOT).as_posix()
        digest.update(relative_path.encode("utf-8") + b"\0" + sha256(path.read_bytes()).encode("ascii") + b"\n")
    return len(paths), digest.hexdigest()


def current_source_lock() -> dict:
    return {
        "sourceTrees": {
            name: {"sourceFileCount": count, "pathAndContentSHA256": fingerprint}
            for name in SOURCE_TREES
            for count, fingerprint in (source_tree_fingerprint(name),)
        },
        "files": {name: sha256((ROOT / name).read_bytes()) for name in LOCKED_FILES},
    }


@cache
def historical_source_lock(revision: str = PRIOR_EVIDENCE_REVISION) -> dict:
    """Rebuild v2's generator fingerprint from the commit that sealed v2.

    A later Core/Validation edit cannot silently rebind v2 to current source.
    Missing Git history is an infrastructure error, not a checksum mismatch.
    """
    available = subprocess.run(
        ["git", "cat-file", "-e", f"{revision}^{{commit}}"],
        cwd=ROOT, capture_output=True, check=False,
    )
    if available.returncode != 0:
        raise RuntimeError(f"sealed v2 Git revision unavailable: {revision}")

    def blob(path: str) -> bytes:
        result = subprocess.run(
            ["git", "show", f"{revision}:{path}"],
            cwd=ROOT, capture_output=True, check=False,
        )
        if result.returncode != 0:
            raise RuntimeError(f"sealed v2 Git blob unavailable: {revision}:{path}")
        return result.stdout

    trees = {}
    for relative_dir in SOURCE_TREES:
        listing = subprocess.run(
            ["git", "ls-tree", "-r", "--name-only", revision, "--", relative_dir],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )
        if listing.returncode != 0:
            raise RuntimeError(f"cannot list sealed v2 source tree: {relative_dir}")
        paths = sorted(path for path in listing.stdout.splitlines() if path.startswith(relative_dir + "/"))
        if not paths:
            raise ValueError(f"sealed v2 source tree empty: {relative_dir}")
        digest = hashlib.sha256()
        for path in paths:
            digest.update(path.encode("utf-8") + b"\0" + sha256(blob(path)).encode("ascii") + b"\n")
        trees[relative_dir] = {"sourceFileCount": len(paths), "pathAndContentSHA256": digest.hexdigest()}
    return {
        "sourceTrees": trees,
        "files": {name: sha256(blob(name)) for name in LOCKED_FILES},
    }


def derived_run(root: bytes, ordinal: int) -> tuple[bytes, int, str]:
    digest = hashlib.sha256(root + f"development-confirmation-v2/run/{ordinal}".encode()).digest()
    return digest, int.from_bytes(digest[:8], "big") or 1, digest.hex()[:16]


def derived_document_id(run_digest: bytes, ordinal: int) -> str:
    return hashlib.sha256(run_digest + f"/document/{ordinal}".encode()).hexdigest()[:24]


@cache
def prior_artifact_identities() -> tuple[frozenset[int], frozenset[str], int]:
    """Read all retained pre-v2 JSON identities from the v2-seal Git tree.

    The 24-hex comparison is deliberately conservative: it covers any prior
    opaque document namespace represented in the archived JSON, not only v1's
    `opaqueDocumentDerivationIDs` field.
    """
    available = subprocess.run(
        ["git", "cat-file", "-e", f"{PRIOR_EVIDENCE_REVISION}^{{commit}}"],
        cwd=ROOT, capture_output=True, check=False,
    )
    if available.returncode != 0:
        raise RuntimeError(f"prior evidence Git revision unavailable: {PRIOR_EVIDENCE_REVISION}")
    listing = subprocess.run(
        ["git", "ls-tree", "-r", "--name-only", PRIOR_EVIDENCE_REVISION, "--", *PRIOR_EVIDENCE_ROOTS],
        cwd=ROOT, capture_output=True, text=True, check=False,
    )
    if listing.returncode != 0:
        raise RuntimeError(f"cannot list prior evidence at {PRIOR_EVIDENCE_REVISION}")
    paths = [
        path for path in listing.stdout.splitlines()
        if path.endswith(".json") and path != MANIFEST.relative_to(ROOT).as_posix()
    ]
    if not paths:
        raise ValueError("prior evidence inventory is empty")
    seeds: set[int] = set()
    documents: set[str] = set()

    def collect(value: object, field: str = "") -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                collect(child, key)
        elif isinstance(value, list):
            for child in value:
                collect(child, field)
        elif isinstance(value, int) and not isinstance(value, bool) and "seed" in field.lower():
            seeds.add(value)
        elif isinstance(value, str) and re.fullmatch(r"[0-9a-f]{24}", value):
            documents.add(value)

    for path in paths:
        blob = subprocess.run(
            ["git", "show", f"{PRIOR_EVIDENCE_REVISION}:{path}"],
            cwd=ROOT, capture_output=True, check=False,
        )
        if blob.returncode != 0:
            raise RuntimeError(f"prior evidence Git blob unavailable: {path}")
        try:
            collect(json.loads(blob.stdout))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ValueError(f"invalid prior evidence JSON: {path}") from error
    if not set(KNOWN_DEVELOPMENT_SEEDS).issubset(seeds) \
            or not set(FROZEN_RELEASE_SEEDS).issubset(seeds):
        raise ValueError("prior evidence inventory omitted known development/release seeds")
    return frozenset(seeds), frozenset(documents), len(paths)


def require_disjoint(
    seeds: set[int], documents: set[str],
    prior_seeds: frozenset[int], prior_documents: frozenset[str],
) -> None:
    if seeds & prior_seeds:
        raise ValueError("reserved seeds overlap a prior development/release artifact")
    if documents & prior_documents:
        raise ValueError("reserved document IDs overlap a prior archived opaque identity")


def validate_source_lock(lock: dict, *, verify_files: bool = True) -> None:
    if lock.get("schemaVersion") != 1 or lock.get("lockRole") != "post-extraction-generator-provenance":
        raise ValueError("unsupported extracted-generator source lock")
    if lock.get("sourceRevision") != "b2b99696feda177be0699d5277a2c13c7c7c9bd5":
        raise ValueError("source revision provenance changed")
    if lock.get("workingTreeCleanAtLock") is not False or lock.get("candidateFrozen") is not False:
        raise ValueError("source lock must not claim a clean candidate freeze")
    if lock.get("swiftMode") != "Swift 6" or lock.get("standaloneSwiftFlags") != ["-swift-version", "6", "-warnings-as-errors", "-O"]:
        raise ValueError("Swift 6 build flags changed")
    expected = historical_source_lock() if verify_files else lock.get("generatorInputs", {})
    if set(lock.get("generatorInputs", {}).get("sourceTrees", {})) != set(SOURCE_TREES):
        raise ValueError("source tree coverage changed")
    if set(lock.get("generatorInputs", {}).get("files", {})) != set(LOCKED_FILES):
        raise ValueError("locked file coverage changed")
    if lock.get("generatorInputs") != expected:
        raise ValueError("sealed v2 historical generator source/build inputs changed")
    if lock.get("analysisBinding", {}).get("status") != "provenanceOnlyNotFrozen":
        raise ValueError("analysis binding incorrectly claims a candidate freeze")
    if lock["analysisBinding"].get("paths") != [
        "scripts/validate_vocabulary_assessment_report.py",
        "scripts/summarize_vocabulary_assessment_benchmarks.py",
        "scripts/compare_vocabulary_stopping_reports.py",
        "docs/plans/vocabulary-measurement-coherence/target-ledger.json",
    ]:
        raise ValueError("analysis binding paths changed")
    if lock["analysisBinding"].get("candidateAnalysisAndDecisionRulesChecksum") is not None:
        raise ValueError("analysis/decision rules cannot be frozen by the extraction")
    if verify_files and (lock.get("parityManifestSHA256") != sha256(PARITY_MANIFEST.read_bytes())
                         or lock.get("postExtractionParityReportSHA256") != sha256(PARITY_REPORT.read_bytes())):
        raise ValueError("extraction parity evidence changed")
    if lock.get("protectedOutcomesAccessed") is not False:
        raise ValueError("source lock must not claim protected outcome access")


def validate(manifest: dict, *, verify_files: bool = True) -> dict:
    if manifest.get("schemaVersion") != 2 or manifest.get("reservationID") != "development-confirmation-v2":
        raise ValueError("unsupported fresh development-confirmation reservation")
    if manifest.get("dataRole") != "development-confirmation" or manifest.get("executionStatus") != "reservedNotExecuted":
        raise ValueError("reservation role/status changed")
    if manifest.get("supersedesAsActiveReservation") != "development-confirmation-v1":
        raise ValueError("historical reservation relationship changed")
    if manifest.get("historicalReservationStatus") != "reservedNotExecuted":
        raise ValueError("historical reservation cannot be consumed")
    if manifest.get("reservationBaseRevision") != "b2b99696feda177be0699d5277a2c13c7c7c9bd5":
        raise ValueError("reservation base revision changed")

    derivation = manifest.get("seedDerivation", {})
    root = derivation.get("seedDerivationRoot", "")
    if not isinstance(root, str) or not re.fullmatch(r"[0-9a-f]{64}", root):
        raise ValueError("seed derivation root must be 32 lowercase-hex bytes")
    if derivation.get("algorithm") != "SHA256(rootBytes || UTF8('development-confirmation-v2/run/' || zeroBasedRunOrdinal)); seed=first8BytesUInt64BE, zero maps to one":
        raise ValueError("seed derivation algorithm changed")
    if derivation.get("documentIdentityAlgorithm") != "first24Hex(SHA256(fullRunDigest || UTF8('/document/' || zeroBasedDocumentOrdinal)))":
        raise ValueError("document derivation algorithm changed")
    workload = manifest.get("workload", {})
    if workload.get("readersPerScenario") != 64 or workload.get("documentsPerScenario") != 8 or workload.get("lemmasPerDocument") != 400:
        raise ValueError("confirmation workload changed")
    if workload.get("scenarios") != ["well-specified", "item-residual", "response-noise", "idiosyncratic-knowledge"]:
        raise ValueError("confirmation scenarios changed")
    if workload.get("modes") != ["all-unknown", "coverage-98"] or workload.get("warmAndCold") is not True:
        raise ValueError("confirmation modes changed")

    runs = manifest.get("runs")
    if not isinstance(runs, list) or len(runs) != 3:
        raise ValueError("reservation must contain exactly three runs")
    seeds: list[int] = []
    documents: list[str] = []
    for ordinal, run in enumerate(runs):
        digest, seed, run_id = derived_run(bytes.fromhex(root), ordinal)
        expected_documents = [derived_document_id(digest, index) for index in range(8)]
        if run.get("runOrdinal") != ordinal or run.get("runID") != run_id or run.get("seed") != seed:
            raise ValueError(f"run {ordinal} seed identity changed")
        if run.get("opaqueDocumentDerivationIDs") != expected_documents:
            raise ValueError(f"run {ordinal} document identities changed")
        seeds.append(seed)
        documents.extend(expected_documents)
    if len(set(seeds)) != len(seeds) or len(set(documents)) != len(documents):
        raise ValueError("duplicate reserved identity")

    if sha256(HISTORICAL_MANIFEST.read_bytes()) != HISTORICAL_SHA256:
        raise ValueError("historical reservation bytes changed")
    historical = read_json(HISTORICAL_MANIFEST)
    if historical.get("executionStatus") != "reservedNotExecuted":
        raise ValueError("historical reservation was executed")
    older_seeds = {run["seed"] for run in historical["runs"]}
    older_documents = {document for run in historical["runs"] for document in run["opaqueDocumentDerivationIDs"]}
    prior_seeds, prior_documents, _ = prior_artifact_identities()
    require_disjoint(set(seeds), set(documents), prior_seeds, prior_documents)
    if not older_seeds.issubset(prior_seeds) or not older_documents.issubset(prior_documents):
        raise ValueError("prior evidence inventory omitted the historical reservation")
    non_overlap = manifest.get("nonOverlap", {})
    if non_overlap.get("knownDevelopmentSeeds") != list(KNOWN_DEVELOPMENT_SEEDS) \
            or non_overlap.get("frozenReleaseHoldoutSeeds") != list(FROZEN_RELEASE_SEEDS) \
            or non_overlap.get("historicalReservationSHA256") != HISTORICAL_SHA256 \
            or non_overlap.get("allReservedSeedsMustBeDisjoint") is not True \
            or non_overlap.get("allOpaqueDocumentDerivationIDsMustBeUnique") is not True:
        raise ValueError("known seed non-overlap registry changed")

    source_lock = manifest.get("generatorLock", {})
    if source_lock.get("path") != SOURCE_LOCK.relative_to(ROOT).as_posix():
        raise ValueError("generator source-lock path changed")
    if not re.fullmatch(r"[0-9a-f]{64}", str(source_lock.get("sha256", ""))):
        raise ValueError("generator source-lock checksum invalid")
    if verify_files:
        source_lock_bytes = SOURCE_LOCK.read_bytes()
        if sha256(source_lock_bytes) != source_lock["sha256"]:
            raise ValueError("generator source-lock checksum mismatch")
        validate_source_lock(json.loads(source_lock_bytes))

    freeze = manifest.get("freezeAndConsumption", {})
    if any(freeze.get(key) is not None for key in ("candidateFreeze", "analysisFreeze", "decisionRulesChecksum", "consumedByCandidateCycle")):
        raise ValueError("reservation prematurely claims a candidate, analysis, or decision freeze")
    if freeze.get("outcomeArtifacts") != [] or freeze.get("outcomesInspected") is not False:
        raise ValueError("unexecuted reservation contains outcome evidence")
    if freeze.get("releaseHoldoutAccessAllowed") is not False:
        raise ValueError("reservation cannot authorize release holdout access")
    if freeze.get("requiredBeforeExecution") != [
        "candidate commit and clean-tree hash",
        "model/configuration/resource hashes",
        "analysis and decision-rule checksum",
        "reviewed decision to consume this specific reservation",
    ]:
        raise ValueError("execution prerequisites changed")
    return {"reservationID": manifest["reservationID"], "executionStatus": "reservedNotExecuted", "runs": 3, "documents": 24}


def self_test() -> None:
    original = read_json(MANIFEST)
    validate(original)
    prior_seeds, prior_documents, file_count = prior_artifact_identities()
    if file_count < 100 or not {1, 2, 7, 17, 20260909, 20260912, 20260913, 20260914}.issubset(prior_seeds):
        raise AssertionError("versioned prior development inventory is incomplete")
    first_seed = original["runs"][0]["seed"]
    first_document = original["runs"][0]["opaqueDocumentDerivationIDs"][0]
    for seed_set, document_set in (
        (prior_seeds | {first_seed}, prior_documents),
        (prior_seeds, prior_documents | {first_document}),
    ):
        try:
            require_disjoint({first_seed}, {first_document}, seed_set, document_set)
        except ValueError:
            pass
        else:
            raise AssertionError("accepted a synthetic prior-identity collision")
    mutations = (
        ("seed", lambda value: value["runs"][0].__setitem__("seed", 1)),
        ("document", lambda value: value["runs"][1]["opaqueDocumentDerivationIDs"].__setitem__(0, "0" * 24)),
        ("status", lambda value: value.__setitem__("executionStatus", "executed")),
        ("outcome", lambda value: value["freezeAndConsumption"]["outcomeArtifacts"].append("result.json")),
        ("source lock", lambda value: value["generatorLock"].__setitem__("sha256", "0" * 64)),
    )
    for label, mutate in mutations:
        changed = copy.deepcopy(original)
        mutate(changed)
        try:
            validate(changed)
        except ValueError:
            continue
        raise AssertionError(f"accepted changed {label}")
    lock = read_json(SOURCE_LOCK)
    changed_lock = copy.deepcopy(lock)
    changed_lock["generatorInputs"]["files"]["Package.swift"] = "0" * 64
    try:
        validate_source_lock(changed_lock)
    except ValueError:
        pass
    else:
        raise AssertionError("accepted mismatched source bytes")
    try:
        historical_source_lock("f" * 40)
    except RuntimeError:
        pass
    else:
        raise AssertionError("accepted unavailable sealed Git revision")
    real_read_bytes = Path.read_bytes

    def missing_source_lock(path: Path) -> bytes:
        if path == SOURCE_LOCK:
            raise FileNotFoundError("synthetic missing source lock")
        return real_read_bytes(path)

    with patch.object(Path, "read_bytes", missing_source_lock):
        try:
            validate(original)
        except FileNotFoundError:
            pass
        else:
            raise AssertionError("accepted missing source lock")
    print("post-extraction development-confirmation reservation self-test passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--print-current-lock", action="store_true")
    args = parser.parse_args()
    if args.print_current_lock:
        print(json.dumps(current_source_lock(), indent=2, sort_keys=True))
        return
    if RESERVATION_SHA256 == "TO_BE_FROZEN" or sha256(MANIFEST.read_bytes()) != RESERVATION_SHA256:
        raise ValueError("fresh reservation is missing or differs from its frozen checksum")
    if args.self_test:
        self_test()
    else:
        print(json.dumps(validate(read_json(MANIFEST)), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
