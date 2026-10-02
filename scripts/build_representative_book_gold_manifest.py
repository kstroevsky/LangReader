#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


VALID_POS = {
    "noun",
    "verb",
    "adjective",
    "adverb",
    "pronoun",
    "determiner",
    "preposition",
    "conjunction",
    "interjection",
    "particle",
    "other",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def annotation_files(paths: list[Path], directories: list[Path]) -> list[Path]:
    values = [path.expanduser().resolve() for path in paths]
    for directory in directories:
        values.extend(sorted(directory.expanduser().resolve().rglob("*.json")))
    return sorted(set(values))


def read_annotation(path: Path) -> dict | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if value.get("schemaVersion") != 2:
        return None
    if not isinstance(value.get("source"), dict) or not isinstance(value.get("anchors"), list):
        return None
    return value


def build_gold_manifest(
    corpus: dict,
    files: list[Path],
    role: str,
    panel: str,
    freeze: bool,
    require_all: bool,
) -> dict:
    if role == "confirmatory" and panel != "representative":
        raise ValueError("confirmatory gold must use the representative panel")
    if panel not in {"representative", "challenge"}:
        raise ValueError(f"unsupported gold panel {panel!r}")

    documents = [row for row in corpus["documents"] if row["dataRole"] == role]
    by_source = {row["sourceSHA256"]: row for row in documents}
    if len(by_source) != len(documents):
        raise ValueError("corpus contains duplicate source hashes in the selected role")

    rows: list[dict] = []
    seen_sources: set[str] = set()
    expected_representative = corpus["samplingPolicies"]["representative"]
    expected_challenge = corpus["samplingPolicies"]["developmentChallenge"]
    expected_policy = (
        expected_representative if panel == "representative" else expected_challenge
    )

    for path in files:
        annotation = read_annotation(path)
        if annotation is None:
            continue
        source = annotation["source"]
        source_hash = source.get("sourceSHA256")
        document = by_source.get(source_hash)
        if document is None:
            continue
        annotation_panel = annotation.get("panel")
        if annotation_panel != panel:
            continue
        if source_hash in seen_sources:
            raise ValueError(f"multiple annotation files match {document['documentID']}")
        if source.get("dataRole") != role:
            raise ValueError(f"{path}: annotation role does not match corpus role")
        if source.get("documentFormat") != document.get("documentFormat"):
            raise ValueError(f"{path}: annotation format does not match corpus manifest")
        if source.get("languageCode") != document.get("language"):
            raise ValueError(f"{path}: annotation language does not match corpus manifest")

        policy = annotation.get("candidateSelectionPolicyVersion")
        if policy != expected_policy:
            raise ValueError(
                f"{path}: {panel} gold must use candidate-selection policy {expected_policy}"
            )

        approved = 0
        rejected = 0
        unreviewed = 0
        occurrence_ids: set[str] = set()
        for anchor in annotation["anchors"]:
            for occurrence in anchor.get("occurrences", []):
                occurrence_id = occurrence.get("occurrenceID")
                if not isinstance(occurrence_id, str) or not occurrence_id:
                    raise ValueError(f"{path}: annotation occurrence is missing occurrenceID")
                if occurrence_id in occurrence_ids:
                    raise ValueError(f"{path}: duplicate occurrenceID {occurrence_id}")
                occurrence_ids.add(occurrence_id)
                status = occurrence.get("reviewStatus")
                if status == "approved":
                    lemma = occurrence.get("goldLemma")
                    part = occurrence.get("goldPartOfSpeech")
                    if not isinstance(lemma, str) or not lemma.strip():
                        raise ValueError(f"{path}: approved occurrence {occurrence_id} has no gold lemma")
                    if part not in VALID_POS:
                        raise ValueError(f"{path}: approved occurrence {occurrence_id} has invalid gold POS")
                    approved += 1
                elif status in {"unreviewed", None, ""}:
                    unreviewed += 1
                else:
                    rejected += 1

        if freeze and unreviewed:
            raise ValueError(f"{path}: cannot freeze gold with {unreviewed} unreviewed occurrences")
        if freeze and approved == 0:
            raise ValueError(f"{path}: cannot freeze gold with no approved occurrences")

        sampled_units = source.get("sampledUnitNumbers")
        if not isinstance(sampled_units, list) or not sampled_units:
            raise ValueError(f"{path}: annotation is missing sampled-unit provenance")
        sampled_hash = annotation.get("sampledTextSHA256")
        if not isinstance(sampled_hash, str) or len(sampled_hash) != 64:
            raise ValueError(f"{path}: annotation is missing sampled-text SHA-256")

        rows.append(
            {
                "documentID": document["documentID"],
                "workFamilyID": document["workFamilyID"],
                "sourceSHA256": source_hash,
                "annotationAlias": source.get("alias"),
                "annotationSHA256": sha256_file(path),
                "sampledTextSHA256": sampled_hash,
                "sampledUnitNumbers": sampled_units,
                "candidateSelectionPolicyVersion": policy,
                "approvedOccurrenceCount": approved,
                "rejectedOccurrenceCount": rejected,
                "unreviewedOccurrenceCount": unreviewed,
            }
        )
        seen_sources.add(source_hash)

    missing = [row["documentID"] for row in documents if row["sourceSHA256"] not in seen_sources]
    if (freeze or require_all) and missing:
        raise ValueError(f"gold manifest is missing {len(missing)} selected documents: {', '.join(missing[:8])}")
    if not rows:
        raise ValueError("no schema-v2 annotations matched the selected corpus role")

    rows.sort(key=lambda row: row["documentID"])
    return {
        "schemaVersion": 1,
        "protocolVersion": corpus["protocolVersion"],
        "dataRole": role,
        "panel": panel,
        "status": "frozen" if freeze else "draft",
        "containsExtractedProse": False,
        "checkpoints": corpus["checkpoints"],
        "documentCount": len(rows),
        "documents": rows,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus-manifest", type=Path, required=True)
    parser.add_argument("--annotation", type=Path, action="append", default=[])
    parser.add_argument("--annotation-dir", type=Path, action="append", default=[])
    parser.add_argument("--role", choices=["development", "confirmatory"], required=True)
    parser.add_argument("--panel", choices=["representative", "challenge"])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--freeze", action="store_true")
    parser.add_argument("--require-all", action="store_true")
    args = parser.parse_args()

    corpus = json.loads(args.corpus_manifest.read_text(encoding="utf-8"))
    files = annotation_files(args.annotation, args.annotation_dir)
    if not files:
        parser.error("provide at least one --annotation or --annotation-dir")
    if args.role == "development" and args.panel is None:
        parser.error("--panel is required for development gold")
    panel = args.panel or "representative"
    if args.role == "confirmatory" and panel != "representative":
        parser.error("confirmatory gold must use --panel representative")
    manifest = build_gold_manifest(
        corpus,
        files,
        args.role,
        panel,
        args.freeze,
        args.require_all,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(
        f"wrote {manifest['status']} {args.role} {panel} gold manifest: "
        f"{manifest['documentCount']} documents"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
