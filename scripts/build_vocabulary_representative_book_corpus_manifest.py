#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path


SCHEMA_VERSION = 1
CHECKPOINTS = {
    "A": "d74a198551f437814b6f305342c235523ecf8df3",
    "B": "ac321721cdd52d966cc859040106feb544a67735",
    "C": "970b049d7aa3a0770c6b9dfa84e6b40e6e327da9",
}

GENRE_BY_AUTHOR = {
    "Andrew Hunt, David Thomas": "technical-scientific",
    "Anton Hur": "literary-fiction",
    "Carlo Rovelli": "popular-non-fiction",
    "Christopher Clark": "non-fiction",
    "Clayton Christensen": "popular-non-fiction",
    "Cormac McCarthy": "literary-fiction",
    "Daniel Kahneman": "popular-non-fiction",
    "Daniel Kehlmann": "literary-fiction",
    "Dudenredaktion": "reference",
    "Ed Yong": "popular-non-fiction",
    "Eliyahu M. Goldratt, Jeff Cox": "popular-non-fiction",
    "Elmore Leonard": "literary-fiction",
    "Eric Matthes": "technical-scientific",
    "Friedrich Dürrenmatt": "literary-fiction",
    "George Saunders": "literary-fiction",
    "Gillian Flynn": "literary-fiction",
    "Jenny Erpenbeck": "literary-fiction",
    "John Carreyrou": "non-fiction",
    "John Hersey": "non-fiction",
    "Juli Zeh": "literary-fiction",
    "Kazuo Ishiguro": "literary-fiction",
    "Martin Kleppmann": "technical-scientific",
    "Mary Beard": "non-fiction",
    "Nell Zink": "literary-fiction",
    "Patrick Radden Keefe": "non-fiction",
    "Rachel Kushner": "literary-fiction",
    "Richard Osman": "literary-fiction",
    "Robert Menasse": "literary-fiction",
    "Sally Rooney": "literary-fiction",
    "Samin Nosrat": "popular-non-fiction",
    "Saša Stanišić": "biography-memoir",
    "Siddhartha Mukherjee": "popular-non-fiction",
    "Svetlana Alexievich": "non-fiction",
    "Tara Westover": "biography-memoir",
    "Trevor Noah": "biography-memoir",
    "University of Chicago Press Editorial Staff": "reference",
    "Vaclav Smil": "popular-non-fiction",
    "Walter Isaacson": "biography-memoir",
    "Wolf Haas": "literary-fiction",
    "Zadie Smith": "literary-fiction",
}


def nfc(value: str) -> str:
    return unicodedata.normalize("NFC", value)


def slug(value: str) -> str:
    ascii_value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode("ascii")
    normalized = re.sub(r"[^a-z0-9]+", "-", ascii_value.lower()).strip("-")
    return normalized or "document"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_name(path: Path) -> tuple[str | None, str, str]:
    stem = nfc(path.stem)
    match = re.match(r"^(?:(.*?) - )?(.*?) \[(English|German)\]$", stem)
    if not match:
        raise ValueError(f"unexpected corpus filename: {path.name}")
    author, title, language_name = match.groups()
    normalized_author = nfc(author) if author else None
    normalized_title = nfc(title)
    if normalized_author == "GDPR" and normalized_title == "DSGVO":
        normalized_author = None
        normalized_title = "GDPR / DSGVO"
    return normalized_author, normalized_title, "en" if language_name == "English" else "de"


def paired_family(author: str | None, title: str) -> str:
    if author is None:
        if title in {"GDPR", "GDPR / DSGVO"}:
            return "gdpr"
        return slug(title)
    if author == "Christopher Clark":
        if title in {"The Sleepwalkers", "Die Schlafwandler"}:
            return "christopher-clark-sleepwalkers"
        if title in {"Revolutionary Spring", "Frühling der Revolution"}:
            return "christopher-clark-revolutionary-spring"
    return slug(author)


def known_cross_cohort_family(author: str | None, title: str) -> str | None:
    if author == "Patrick Radden Keefe" and title in {"Say Nothing", "Sage nichts"}:
        return "patrick-radden-keefe-say-nothing"
    if author == "Saša Stanišić" and title in {"Herkunft", "Where You Come From"}:
        return "sasa-stanisic-herkunft"
    return None


def role_for(cohort: str, author: str | None) -> str:
    if cohort != "en+de":
        return "development"
    if author in {"Patrick Radden Keefe", "Saša Stanišić"}:
        return "development"
    return "confirmatory"


def document_record(root: Path, path: Path) -> dict:
    rel = path.relative_to(root).as_posix()
    cohort = path.relative_to(root).parts[0]
    author, title, language = parse_name(path)
    data_role = role_for(cohort, author)
    cross_cohort_family = known_cross_cohort_family(author, title)
    if cross_cohort_family is not None:
        work_family = cross_cohort_family
    elif cohort == "en+de":
        work_family = paired_family(author, title)
    else:
        work_family = f"{slug(author) if author else 'unattributed'}-{slug(title)}"
    digest = sha256_file(path)
    return {
        "documentID": hashlib.sha256(nfc(rel).encode("utf-8")).hexdigest()[:16],
        "relativePath": rel,
        "fileName": path.name,
        "sourceSHA256": digest,
        "byteCount": path.stat().st_size,
        "language": language,
        "documentFormat": path.suffix.lower().lstrip("."),
        "cohort": cohort,
        "author": author,
        "title": title,
        "authorCluster": slug(author) if author else f"unattributed-{slug(title)}",
        "workFamilyID": work_family,
        "genre": (
            "legal-regulatory"
            if author is None and title in {"EU AI Act", "GDPR"}
            else GENRE_BY_AUTHOR.get(author or "", "unclassified")
        ),
        "period": "pendingBlindAssessment",
        "extractionQuality": "pendingBlindAssessment",
        "lengthBand": "pendingBlindAssessment",
        "dialogueDensity": "pendingBlindAssessment",
        "typography": "pendingBlindAssessment",
        "dataRole": data_role,
        "plannedPanels": ["challenge", "representative"] if data_role == "development" else ["representative"],
        "annotationStatus": "unreviewed",
        "goldFreezeSHA256": None,
    }


def build_manifest(root: Path) -> dict:
    paths = sorted(
        path for path in root.rglob("*")
        if path.is_file() and path.suffix.lower() in {".pdf", ".epub"}
    )
    documents = [document_record(root, path) for path in paths]
    return {
        "schemaVersion": SCHEMA_VERSION,
        "protocolVersion": "representative-book-validation-v1",
        "sourceRootHint": "~/Desktop/books",
        "containsExtractedProse": False,
        "checkpoints": CHECKPOINTS,
        "roleFreezePolicy": {
            "rule": "standalone en/de cohorts are development; en+de cohort is confirmatory except work families already represented in standalone development",
            "translationFamilyMustShareRole": True,
            "modelOutputsUsedForRoleAssignment": False,
        },
        "samplingPolicies": {
            "developmentChallenge": "representative-book-challenge-v3",
            "representative": "representative-book-representative-v2",
        },
        "documentCount": len(documents),
        "documents": documents,
    }


def validate_manifest(manifest: dict) -> list[str]:
    errors: list[str] = []
    if manifest.get("schemaVersion") != SCHEMA_VERSION:
        errors.append("unexpected schemaVersion")
    if manifest.get("containsExtractedProse") is not False:
        errors.append("manifest must not contain extracted prose")
    if manifest.get("checkpoints") != CHECKPOINTS:
        errors.append("checkpoint SHAs differ from frozen A/B/C revisions")

    documents = manifest.get("documents")
    if not isinstance(documents, list) or not documents:
        return errors + ["documents must be a non-empty list"]

    ids: set[str] = set()
    paths: set[str] = set()
    family_roles: dict[str, set[str]] = defaultdict(set)
    counts = Counter()
    for row in documents:
        document_id = row.get("documentID")
        relative_path = row.get("relativePath")
        if not isinstance(document_id, str) or document_id in ids:
            errors.append(f"duplicate/invalid documentID: {document_id!r}")
        ids.add(document_id)
        if not isinstance(relative_path, str) or relative_path.startswith("/") or relative_path in paths:
            errors.append(f"duplicate/invalid relativePath: {relative_path!r}")
        paths.add(relative_path)
        digest = row.get("sourceSHA256")
        if not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{64}", digest) is None:
            errors.append(f"invalid source hash for {relative_path}")
        role = row.get("dataRole")
        if role not in {"development", "confirmatory", "excluded"}:
            errors.append(f"invalid role for {relative_path}: {role!r}")
        panels = row.get("plannedPanels")
        if role == "confirmatory" and panels != ["representative"]:
            errors.append(f"confirmatory source is not prediction-independent: {relative_path}")
        family_roles[str(row.get("workFamilyID"))].add(str(role))
        counts[(role, row.get("language"), row.get("documentFormat"))] += 1

    for family, roles in family_roles.items():
        if len(roles) != 1:
            errors.append(f"work family crosses data roles: {family} -> {sorted(roles)}")

    if manifest.get("documentCount") != len(documents):
        errors.append("documentCount does not match documents array")
    for role in ("development", "confirmatory"):
        for language in ("en", "de"):
            for document_format in ("pdf", "epub"):
                if counts[(role, language, document_format)] == 0:
                    errors.append(f"missing {role} {language}/{document_format} stratum")
    return errors


def holdout_manifest(corpus: dict) -> dict:
    documents = [row for row in corpus["documents"] if row["dataRole"] == "confirmatory"]
    return {
        "schemaVersion": 1,
        "protocolVersion": corpus["protocolVersion"],
        "checkpoints": corpus["checkpoints"],
        "selectionStatus": "roleFrozenGoldNotAnnotated",
        "containsExtractedProse": False,
        "samplingPolicy": "representative-book-representative-v2",
        "goldMustFreezeBeforeCheckpointOutputs": True,
        "documents": documents,
    }


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus-root", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--holdout-output", type=Path)
    parser.add_argument("--validate", type=Path)
    args = parser.parse_args()

    if args.validate:
        manifest = json.loads(args.validate.read_text(encoding="utf-8"))
        errors = validate_manifest(manifest)
        if errors:
            raise SystemExit("\n".join(errors))
        print(f"representative-book corpus manifest valid: {len(manifest['documents'])} documents")
        return 0

    if not args.corpus_root or not args.output or not args.holdout_output:
        parser.error("--corpus-root, --output, and --holdout-output are required when building")
    manifest = build_manifest(args.corpus_root.expanduser().resolve())
    errors = validate_manifest(manifest)
    if errors:
        raise SystemExit("\n".join(errors))
    write_json(args.output, manifest)
    write_json(args.holdout_output, holdout_manifest(manifest))
    counts = Counter(row["dataRole"] for row in manifest["documents"])
    print(f"wrote corpus manifest: {len(manifest['documents'])} documents {dict(counts)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
