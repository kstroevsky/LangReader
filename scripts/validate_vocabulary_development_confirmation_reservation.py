#!/usr/bin/env python3
"""Validate the sealed, deliberately unexecuted development-confirmation set."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import subprocess
from pathlib import Path
from typing import Callable


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "docs/plans/vocabulary-validation-evidence/development-confirmation-reservation-v1.json"


class HistoricalGitObjectUnavailable(RuntimeError):
    """The checkout lacks a commit needed to verify an immutable source lock."""


def historical_blob(revision: str, relative_path: str) -> bytes:
    if not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("reservation revision must be a full lowercase Git commit ID")
    path = Path(relative_path)
    if path.is_absolute() or not path.parts or ".." in path.parts:
        raise ValueError(f"invalid generator lock path: {relative_path}")
    available = subprocess.run(
        ["git", "cat-file", "-e", f"{revision}^{{commit}}"],
        cwd=ROOT,
        capture_output=True,
        check=False,
    )
    if available.returncode != 0:
        raise HistoricalGitObjectUnavailable(
            f"historical Git commit unavailable: {revision}; fetch locked history before validation"
        )
    blob = subprocess.run(
        ["git", "show", f"{revision}:{relative_path}"],
        cwd=ROOT,
        capture_output=True,
        check=False,
    )
    if blob.returncode != 0:
        raise ValueError(f"generator lock path absent at {revision}: {relative_path}")
    return blob.stdout


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def derived_run(root: bytes, ordinal: int) -> tuple[bytes, int, str]:
    digest = hashlib.sha256(root + f"development-confirmation-v1/run/{ordinal}".encode()).digest()
    seed = int.from_bytes(digest[:8], "big") or 1
    return digest, seed, digest.hex()[:16]


def derived_document_id(run_digest: bytes, ordinal: int) -> str:
    return hashlib.sha256(run_digest + f"/document/{ordinal}".encode()).hexdigest()[:24]


def validate(
    manifest: dict,
    *,
    verify_files: bool = True,
    blob_reader: Callable[[str, str], bytes] = historical_blob,
) -> dict:
    if manifest.get("schemaVersion") != 1 or manifest.get("reservationID") != "development-confirmation-v1":
        raise ValueError("unsupported development-confirmation reservation")
    if manifest.get("dataRole") != "development-confirmation":
        raise ValueError("reservation has the wrong synthetic data role")
    if manifest.get("executionStatus") != "reservedNotExecuted":
        raise ValueError("reservation must remain explicitly unexecuted")

    seed_root = manifest.get("seedDerivation", {}).get("seedDerivationRoot", "")
    if not re.fullmatch(r"[0-9a-f]{64}", seed_root):
        raise ValueError("seed derivation root must be 32 lowercase-hex bytes")
    root_bytes = bytes.fromhex(seed_root)
    workload = manifest.get("workload", {})
    if workload.get("readersPerScenario") != 64 or workload.get("documentsPerScenario") != 8 or workload.get("lemmasPerDocument") != 400:
        raise ValueError("reserved workload changed")

    runs = manifest.get("runs")
    if not isinstance(runs, list) or len(runs) != 3:
        raise ValueError("reservation must contain exactly three runs")
    reserved_seeds = []
    document_ids = []
    for expected_ordinal, run in enumerate(runs):
        if run.get("runOrdinal") != expected_ordinal:
            raise ValueError("run ordinals must be unique and contiguous")
        digest, expected_seed, expected_run_id = derived_run(root_bytes, expected_ordinal)
        if run.get("seed") != expected_seed or run.get("runID") != expected_run_id:
            raise ValueError(f"run {expected_ordinal} does not match the committed seed derivation")
        expected_documents = [derived_document_id(digest, index) for index in range(8)]
        if run.get("opaqueDocumentDerivationIDs") != expected_documents:
            raise ValueError(f"run {expected_ordinal} document derivation identities changed")
        reserved_seeds.append(expected_seed)
        document_ids.extend(expected_documents)

    non_overlap = manifest.get("nonOverlap", {})
    prohibited = set(non_overlap.get("knownDevelopmentSeeds", [])) | set(non_overlap.get("frozenReleaseHoldoutSeeds", []))
    if len(set(reserved_seeds)) != len(reserved_seeds) or set(reserved_seeds) & prohibited:
        raise ValueError("reserved seeds overlap development/release seeds or one another")
    if len(set(document_ids)) != len(document_ids):
        raise ValueError("opaque document derivation identities are not unique")

    freeze = manifest.get("freezeAndConsumption", {})
    if freeze.get("candidateFreeze") is not None or freeze.get("analysisFreeze") is not None:
        raise ValueError("unexecuted reservation cannot claim a candidate/analysis freeze")
    if freeze.get("outcomeArtifacts") != [] or freeze.get("outcomesInspected") is not False:
        raise ValueError("unexecuted reservation cannot contain or claim inspected outcomes")
    if freeze.get("consumedByCandidateCycle") is not None or freeze.get("releaseHoldoutAccessAllowed") is not False:
        raise ValueError("unexecuted reservation cannot be consumed or allow release-holdout access")

    if verify_files:
        lock = manifest.get("generatorLock", {})
        revision = manifest.get("reservationRevision")
        for path_key, checksum_key in (
            ("runner", "runnerSHA256"),
            ("evaluator", "evaluatorSHA256"),
            ("causalSupport", "causalSupportSHA256"),
            ("canonicalGateLedger", "canonicalGateLedgerSHA256"),
        ):
            path = lock.get(path_key, "")
            expected_sha256 = lock.get(checksum_key)
            if not isinstance(path, str) or not isinstance(expected_sha256, str) \
                    or not re.fullmatch(r"[0-9a-f]{64}", expected_sha256):
                raise ValueError(f"invalid generator lock: {path_key}")
            actual_sha256 = hashlib.sha256(blob_reader(revision, path)).hexdigest()
            if actual_sha256 != expected_sha256:
                raise ValueError(f"generator lock mismatch: {path}")

    return {
        "reservationID": manifest["reservationID"],
        "executionStatus": manifest["executionStatus"],
        "runs": len(runs),
        "documents": len(document_ids),
        "outcomesInspected": False,
        "releaseHoldoutAccessAllowed": False,
    }


def self_test() -> None:
    manifest = load(DEFAULT_MANIFEST)
    validate(manifest)
    mutations = [
        ("changed seed", lambda value: value["runs"][0].__setitem__("seed", 1)),
        ("changed document", lambda value: value["runs"][1]["opaqueDocumentDerivationIDs"].__setitem__(2, "0" * 24)),
        ("premature outcome", lambda value: value["freezeAndConsumption"]["outcomeArtifacts"].append("result.json")),
        ("premature release access", lambda value: value["freezeAndConsumption"].__setitem__("releaseHoldoutAccessAllowed", True)),
    ]
    for name, mutate in mutations:
        invalid = copy.deepcopy(manifest)
        mutate(invalid)
        try:
            validate(invalid, verify_files=False)
            raise AssertionError(f"{name} was accepted")
        except ValueError:
            pass

    lock = manifest["generatorLock"]
    revision = manifest["reservationRevision"]
    locked_bytes = {
        lock[path_key]: historical_blob(revision, lock[path_key])
        for path_key in ("runner", "evaluator", "causalSupport", "canonicalGateLedger")
    }

    def injected_blob(requested_revision: str, path: str) -> bytes:
        if requested_revision != revision or path not in locked_bytes:
            return b"mismatched historical revision or path"
        return locked_bytes[path]

    lock_mutations = [
        ("mismatched checksum", lambda value: value["generatorLock"].__setitem__("runnerSHA256", "0" * 64)),
        ("mismatched path", lambda value: value["generatorLock"].__setitem__("runner", "scripts/missing-runner.sh")),
        ("mismatched revision", lambda value: value.__setitem__("reservationRevision", "f" * 40)),
    ]
    for name, mutate in lock_mutations:
        invalid = copy.deepcopy(manifest)
        mutate(invalid)
        try:
            validate(invalid, blob_reader=injected_blob)
            raise AssertionError(f"{name} was accepted")
        except ValueError:
            pass

    def mismatched_bytes(requested_revision: str, path: str) -> bytes:
        value = injected_blob(requested_revision, path)
        return value + b"mismatch" if path == lock["runner"] else value

    try:
        validate(manifest, blob_reader=mismatched_bytes)
        raise AssertionError("mismatched historical bytes were accepted")
    except ValueError:
        pass

    def missing_blob(_revision: str, _path: str) -> bytes:
        raise HistoricalGitObjectUnavailable("synthetic shallow checkout")

    try:
        validate(manifest, blob_reader=missing_blob)
        raise AssertionError("missing historical Git object was accepted")
    except HistoricalGitObjectUnavailable:
        pass
    print("vocabulary development-confirmation reservation self-test passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", nargs="?", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    print(json.dumps(validate(load(args.manifest)), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
