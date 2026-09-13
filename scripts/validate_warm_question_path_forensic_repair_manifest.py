#!/usr/bin/env python3
"""Validate the frozen v2 reporting-only warm forensic repair."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path


class ValidationError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ValidationError(message)


def checked_file(root, path, expected_hash, label):
    resolved = root / path
    require(resolved.is_file(), f"{label} missing")
    require(hashlib.sha256(resolved.read_bytes()).hexdigest() == expected_hash, f"{label} checksum mismatch")
    return resolved


def validate(manifest, root):
    require(manifest.get("schemaVersion") == 2, "unsupported schema")
    require(manifest.get("dataRole") == "diagnostic-development-forensic-repair", "invalid data role")
    require(manifest.get("reservationStatus") == "frozen-not-executed", "repair reservation is not sealed")
    require(manifest.get("outcomes") is None, "unexecuted repair contains outcomes")
    require(manifest.get("consumedAtRevision") is None, "unexecuted repair is marked consumed")

    failed = manifest["failedAttempt"]
    original_manifest_path = checked_file(root, failed["manifest"], failed["manifestSHA256"], "v1 manifest")
    checked_file(root, failed["report"], failed["reportSHA256"], "v1 report")
    original = json.loads(original_manifest_path.read_text())
    require(original["reservationStatus"] == "consumed-reporting-incomplete", "v1 failure status changed")

    repair = manifest["repairScope"]
    for key in (
        "selectedRunIDsMustMatchV1", "originalPathMetricsMustMatchV1",
        "questionTracesMustMatchV1", "analysisContractMustMatchV1",
        "noOutcomeDependentSelection",
    ):
        require(repair[key] is True, f"repair invariant relaxed: {key}")
    require(repair["onlyAddedEvidence"] == "final inventory rows for each traced path", "repair scope expanded")
    require(len(repair["finalInventoryFields"]) == 9, "final inventory fields changed")
    require(all(manifest["decisionRule"].values()), "decision boundary relaxed")
    require(all(manifest["forbiddenAccess"].values()), "access boundary relaxed")


def self_test(manifest, root):
    validate(manifest, root)
    mutations = []
    changed_hash = copy.deepcopy(manifest)
    changed_hash["failedAttempt"]["reportSHA256"] = "0" * 64
    mutations.append(changed_hash)
    expanded = copy.deepcopy(manifest)
    expanded["repairScope"]["onlyAddedEvidence"] = "new questions"
    mutations.append(expanded)
    relaxed = copy.deepcopy(manifest)
    relaxed["forbiddenAccess"]["developmentConfirmation"] = False
    mutations.append(relaxed)
    for mutation in mutations:
        try:
            validate(mutation, root)
        except ValidationError:
            continue
        raise AssertionError("invalid forensic repair unexpectedly passed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    manifest = json.loads(args.manifest.read_text())
    if args.self_test:
        self_test(manifest, root)
        print("warm question-path forensic repair self-test passed")
    else:
        validate(manifest, root)
        print("warm question-path forensic repair valid")


if __name__ == "__main__":
    main()
