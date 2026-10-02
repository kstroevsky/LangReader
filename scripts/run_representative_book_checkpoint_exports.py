#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import tempfile
from contextlib import ExitStack
from pathlib import Path


CHECKPOINTS = {
    "A": "d74a198551f437814b6f305342c235523ecf8df3",
    "B": "ac321721cdd52d966cc859040106feb544a67735",
    "C": "970b049d7aa3a0770c6b9dfa84e6b40e6e327da9",
}


def harness_sha256(repo: Path, checkpoint: str) -> str:
    paths = [
        repo / "scripts/representative_book_checkpoint_export_common.swift",
        repo / (
            "scripts/export_representative_book_checkpoint_a.swift"
            if checkpoint == "A"
            else "scripts/export_representative_book_checkpoint_bc.swift"
        ),
        repo / "scripts/run_representative_book_checkpoint_exports.py",
    ]
    digest = hashlib.sha256()
    for path in paths:
        digest.update(path.relative_to(repo).as_posix().encode())
        digest.update(b"\x00")
        digest.update(path.read_bytes())
        digest.update(b"\x00")
    return digest.hexdigest()


def run(command: list[str], cwd: Path, **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(command, cwd=cwd, check=True, text=True, **kwargs)


def archive_checkpoint(repo: Path, revision: str, destination: Path, include_c_app: bool) -> None:
    paths = ["Sources/LeafReaderCore", "scripts/build_core_module.sh"]
    if include_c_app:
        paths.extend([
            "Sources/LeafReaderApp/VocabularyReview/AppleVocabularyLinguisticAnalyzer.swift",
            "Sources/LeafReaderApp/VocabularyReview/AppleVocabularyLanguageRecognizer.swift",
        ])
    archive = subprocess.Popen(
        ["git", "archive", revision, *paths],
        cwd=repo,
        stdout=subprocess.PIPE,
    )
    assert archive.stdout is not None
    try:
        subprocess.run(
            ["tar", "-x", "-C", str(destination)],
            cwd=repo,
            stdin=archive.stdout,
            check=True,
        )
    finally:
        archive.stdout.close()
    status = archive.wait()
    if status != 0:
        raise subprocess.CalledProcessError(status, archive.args)


def compile_exporter(repo: Path, checkpoint: str, revision: str, temp: Path) -> Path:
    archived = temp / "source"
    archived.mkdir()
    archive_checkpoint(repo, revision, archived, include_c_app=checkpoint == "C")
    build = temp / "build"
    build.mkdir()
    run(
        ["bash", "scripts/build_core_module.sh", str(build), "-O", "-warnings-as-errors"],
        cwd=archived,
        stdout=subprocess.DEVNULL,
    )

    output = temp / f"checkpoint-{checkpoint.lower()}-export"
    command = [
        "xcrun", "swiftc",
        "-O", "-warnings-as-errors", "-swift-version", "6", "-parse-as-library",
        "-package-name", "LeafReader",
        "-I", str(build), "-L", str(build), "-lLeafReaderCore",
        "-framework", "NaturalLanguage", "-framework", "CryptoKit",
        str(repo / "scripts/representative_book_checkpoint_export_common.swift"),
    ]
    if checkpoint == "A":
        command.append(str(repo / "scripts/export_representative_book_checkpoint_a.swift"))
    else:
        if checkpoint == "C":
            command.extend([
                "-D", "CHECKPOINT_C",
                str(archived / "Sources/LeafReaderApp/VocabularyReview/AppleVocabularyLinguisticAnalyzer.swift"),
                str(archived / "Sources/LeafReaderApp/VocabularyReview/AppleVocabularyLanguageRecognizer.swift"),
            ])
        command.append(str(repo / "scripts/export_representative_book_checkpoint_bc.swift"))
    command.extend(["-o", str(output)])
    run(command, cwd=repo)
    return output


def validate_export(path: Path, checkpoint: str, bundle: dict, harness_sha: str) -> None:
    value = json.loads(path.read_text(encoding="utf-8"))
    if value.get("schemaVersion") != 1:
        raise ValueError(f"{checkpoint}: unexpected export schema")
    if value.get("checkpoint") != {"id": checkpoint, "revision": CHECKPOINTS[checkpoint]}:
        raise ValueError(f"{checkpoint}: checkpoint provenance mismatch")
    if value.get("sourceSHA256") != bundle["sourceSHA256"]:
        raise ValueError(f"{checkpoint}: source hash mismatch")
    if value.get("annotationSHA256") != bundle["annotationSHA256"]:
        raise ValueError(f"{checkpoint}: annotation hash mismatch")
    if value.get("candidateSelectionPolicyVersion") != bundle["candidateSelectionPolicyVersion"]:
        raise ValueError(f"{checkpoint}: candidate-selection policy mismatch")
    if value.get("sampledTextSHA256") != bundle["sampledTextSHA256"]:
        raise ValueError(f"{checkpoint}: sampled-text hash mismatch")
    if value.get("sampledUnitNumbers") != bundle["sampledUnitNumbers"]:
        raise ValueError(f"{checkpoint}: sampled-unit mismatch")
    environment = value.get("environment")
    if not isinstance(environment, dict):
        raise ValueError(f"{checkpoint}: missing runtime environment provenance")
    for field in (
        "osVersion",
        "osBuildVersion",
        "machineArchitecture",
        "xcodeVersion",
        "swiftVersion",
        "naturalLanguageRuntime",
        "languageSelectionMode",
        "dictionaryAttestationState",
        "experimentHarnessSHA256",
    ):
        if not isinstance(environment.get(field), str) or not environment[field]:
            raise ValueError(f"{checkpoint}: runtime environment is missing {field}")
    if environment["experimentHarnessSHA256"] != harness_sha:
        raise ValueError(f"{checkpoint}: experiment harness hash mismatch")
    records = value.get("records")
    if not isinstance(records, list) or not records:
        raise ValueError(f"{checkpoint}: no occurrence records exported")
    for row in records:
        for field in (
            "assignmentID", "physicalOccurrenceID", "sampledUnitIndex", "sourceUnitNumber",
            "utf16Location", "utf16Length", "surface", "requestedLanguage",
            "contextFingerprint", "providers", "analyses",
        ):
            if field not in row:
                raise ValueError(f"{checkpoint}: record missing {field}")
    if checkpoint == "A":
        if any(row.get("resolutionState") is not None for row in records):
            raise ValueError("A: baseline must not emulate ADR-0001 resolution state")
        if any(row.get("assessmentIdentityPolicy") is not None for row in records):
            raise ValueError("A: baseline must not emulate ADR-0001 assessment identity policy")
    if checkpoint == "B" and any(row.get("detectedLanguage") is not None for row in records):
        raise ValueError("B: pre-ADR-0002 export unexpectedly contains detected language")


def validate_confirmatory_freeze(path: Path | None, bundle: dict, repo: Path) -> None:
    if path is None:
        raise ValueError(
            "confirmatory checkpoint execution requires --confirmatory-freeze after human gold and analysis rules are frozen"
        )
    freeze = json.loads(path.read_text(encoding="utf-8"))
    if freeze.get("status") != "frozen":
        raise ValueError("confirmatory freeze record is not frozen")
    if freeze.get("checkpoints") != CHECKPOINTS:
        raise ValueError("confirmatory freeze record does not match checkpoint A/B/C revisions")
    for field in (
        "corpusManifestSHA256",
        "goldManifestSHA256",
        "analysisRulesSHA256",
        "analysisCodeSHA256",
        "holdoutManifestSHA256",
    ):
        value = freeze.get(field)
        if not isinstance(value, str) or len(value) != 64:
            raise ValueError(f"confirmatory freeze record is missing {field}")
    documents = freeze.get("documents")
    if not isinstance(documents, list):
        raise ValueError("confirmatory freeze record is missing frozen document/sample provenance")
    expected = {
        "sourceSHA256": bundle["sourceSHA256"],
        "annotationSHA256": bundle["annotationSHA256"],
        "sampledTextSHA256": bundle["sampledTextSHA256"],
    }
    if not any(all(row.get(key) == value for key, value in expected.items()) for row in documents):
        raise ValueError("confirmatory sample bundle is not part of the frozen gold population")
    if bundle.get("candidateSelectionPolicyVersion") != freeze.get("samplingPolicy"):
        raise ValueError("confirmatory sample bundle does not use the frozen representative sampling policy")
    expected_harnesses = {
        checkpoint: harness_sha256(repo, checkpoint) for checkpoint in CHECKPOINTS
    }
    if freeze.get("checkpointExportHarnessSHA256") != expected_harnesses:
        raise ValueError("checkpoint export harness changed after confirmatory freeze")


def run_bundle_with_exporters(
    repo: Path,
    bundle_path: Path,
    output_dir: Path,
    checkpoints: list[str],
    executables: dict[str, Path],
    confirmatory_freeze: Path | None = None,
) -> None:
    bundle = json.loads(bundle_path.read_text(encoding="utf-8"))
    if bundle.get("dataRole") == "confirmatory":
        validate_confirmatory_freeze(confirmatory_freeze, bundle, repo)
    output_dir.mkdir(parents=True, exist_ok=True)
    for checkpoint in checkpoints:
        revision = CHECKPOINTS[checkpoint]
        harness_sha = harness_sha256(repo, checkpoint)
        output = output_dir / f"checkpoint-{checkpoint.lower()}.json"
        run(
            [
                str(executables[checkpoint]),
                str(bundle_path),
                str(output),
                checkpoint,
                revision,
                harness_sha,
            ],
            cwd=repo,
        )
        validate_export(output, checkpoint, bundle, harness_sha)
        print(f"validated checkpoint {checkpoint}: {output}")


def export_bundles(
    repo: Path,
    bundle_paths: list[Path],
    output_dir: Path,
    checkpoints: list[str],
    confirmatory_freeze: Path | None = None,
) -> None:
    bundles = [
        (path, json.loads(path.read_text(encoding="utf-8")))
        for path in bundle_paths
    ]
    aliases = [value.get("documentAlias") for _, value in bundles]
    if any(not isinstance(alias, str) or not alias for alias in aliases):
        raise ValueError("every sample bundle must have a non-empty documentAlias")
    if len(set(aliases)) != len(aliases):
        raise ValueError("sample bundle documentAlias values must be unique in a batch")

    with ExitStack() as stack:
        executables: dict[str, Path] = {}
        for checkpoint in checkpoints:
            raw_temp = stack.enter_context(
                tempfile.TemporaryDirectory(
                    prefix=f"leafreader-checkpoint-{checkpoint.lower()}-"
                )
            )
            executables[checkpoint] = compile_exporter(
                repo,
                checkpoint,
                CHECKPOINTS[checkpoint],
                Path(raw_temp),
            )

        multiple = len(bundle_paths) > 1
        for (bundle_path, bundle), alias in zip(bundles, aliases):
            destination = output_dir / alias if multiple else output_dir
            if bundle.get("dataRole") == "confirmatory":
                validate_confirmatory_freeze(confirmatory_freeze, bundle, repo)
            run_bundle_with_exporters(
                repo,
                bundle_path,
                destination,
                checkpoints,
                executables,
                confirmatory_freeze,
            )


def export_bundle(
    repo: Path,
    bundle_path: Path,
    output_dir: Path,
    checkpoints: list[str],
    confirmatory_freeze: Path | None = None,
) -> None:
    export_bundles(
        repo,
        [bundle_path],
        output_dir,
        checkpoints,
        confirmatory_freeze,
    )


def write_self_test_bundle(path: Path) -> None:
    texts = [
        "They record the record every day. The record can record another event.",
        "A bright light can light the room while the light remains visible.",
    ]
    joined = "\n\x1e\n".join(texts)
    value = {
        "schemaVersion": 1,
        "documentAlias": "checkpoint-export-self-test",
        "sourceSHA256": "0" * 64,
        "annotationSHA256": "1" * 64,
        "candidateSelectionPolicyVersion": "representative-book-challenge-v3",
        "sampledTextSHA256": hashlib.sha256(joined.encode()).hexdigest(),
        "languageCode": "en",
        "documentFormat": "pdf",
        "dataRole": "development",
        "sourceUnitKind": "synthetic-unit",
        "sourceUnitCount": 2,
        "sampledUnitNumbers": [1, 2],
        "sampledTexts": texts,
        "containsExtractedProse": True,
    }
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", type=Path, action="append")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--checkpoint", choices=["A", "B", "C", "all"], default="all")
    parser.add_argument("--confirmatory-freeze", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    checkpoints = list(CHECKPOINTS) if args.checkpoint == "all" else [args.checkpoint]

    if args.self_test:
        with tempfile.TemporaryDirectory(prefix="leafreader-checkpoint-export-self-test-") as raw_temp:
            temp = Path(raw_temp)
            bundle = temp / "bundle.json"
            write_self_test_bundle(bundle)
            export_bundle(repo, bundle, temp / "out", checkpoints)
        print("representative-book checkpoint exporter self-test passed")
        return 0

    if not args.bundle or not args.output_dir:
        parser.error("--bundle and --output-dir are required")
    export_bundles(
        repo,
        [path.resolve() for path in args.bundle],
        args.output_dir.resolve(),
        checkpoints,
        args.confirmatory_freeze.resolve() if args.confirmatory_freeze else None,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
