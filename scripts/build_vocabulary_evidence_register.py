#!/usr/bin/env python3
"""Build the derived vocabulary evidence/status register without changing its ledger."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC_PATH = ROOT / "docs/plans/vocabulary-validation-evidence/evidence-status-spec-v1.json"
JSON_PATH = ROOT / "docs/plans/vocabulary-validation-evidence/evidence-status-register-v1.json"
MARKDOWN_PATH = ROOT / "docs/plans/vocabulary-validation-evidence/evidence-status-register-v1.md"
VALID_STATUSES = {
    "implemented",
    "historically_measured",
    "verified_current_candidate",
    "implemented_evidence_adverse",
    "failed",
    "awaiting_external_input",
    "deferred",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def build() -> dict:
    spec = load_json(SPEC_PATH)
    if spec.get("schema_version") != 1:
        raise ValueError("status spec schema_version must be 1")
    ledger_path = ROOT / spec["canonical_ledger"]
    ledger = load_json(ledger_path)
    requirements = ledger.get("requirements")
    if not isinstance(requirements, list):
        raise ValueError("canonical ledger requirements must be an array")
    canonical = {requirement["id"]: requirement for requirement in requirements}
    if len(canonical) != len(requirements):
        raise ValueError("canonical ledger IDs must be unique")

    assignments = {}
    required_fields = {
        "prerequisite",
        "responsible_capability",
        "source_revision_configuration",
        "artifact",
        "command_environment",
        "gate",
        "evidence_class",
        "current_status",
        "next_action",
        "decision_history",
    }
    for group in spec.get("groups", []):
        missing = required_fields - set(group)
        if missing:
            raise ValueError(f"group {group.get('name')} is missing {sorted(missing)}")
        if group["current_status"] not in VALID_STATUSES:
            raise ValueError(f"group {group.get('name')} has invalid current_status")
        for requirement_id in group.get("ids", []):
            if requirement_id in assignments:
                raise ValueError(f"requirement assigned twice: {requirement_id}")
            assignments[requirement_id] = group
    if set(assignments) != set(canonical):
        missing = sorted(set(canonical) - set(assignments))
        extra = sorted(set(assignments) - set(canonical))
        raise ValueError(f"status IDs must match canonical ledger; missing={missing}, extra={extra}")

    records = []
    for requirement in requirements:
        group = assignments[requirement["id"]]
        artifact_path = ROOT / group["artifact"]
        if not artifact_path.is_file():
            raise ValueError(f"artifact does not exist: {group['artifact']}")
        records.append({
            "id": requirement["id"],
            "canonical_status": requirement["status"],
            "behavior_claim": requirement["summary"],
            "prerequisite": group["prerequisite"],
            "responsible_capability": group["responsible_capability"],
            "source_revision_configuration": group["source_revision_configuration"],
            "artifact": {
                "path": group["artifact"],
                "sha256": sha256(artifact_path),
            },
            "command_environment": group["command_environment"],
            "gate": group["gate"],
            "evidence_class": group["evidence_class"],
            "current_status": group["current_status"],
            "next_action": group["next_action"],
            "decision_history": group["decision_history"],
        })

    if any(
        (record["canonical_status"] == "deferred") != (record["current_status"] == "deferred")
        for record in records
    ):
        raise ValueError("canonical deferred requirements must remain exactly the derived deferred set")

    retained_artifacts = []
    for item in spec.get("retained_artifacts", []):
        path = ROOT / item["path"]
        if not path.is_file():
            raise ValueError(f"retained artifact does not exist: {item['path']}")
        retained_artifacts.append({**item, "sha256": sha256(path)})

    counts = Counter(record["current_status"] for record in records)
    return {
        "schema_version": 1,
        "derived_view": True,
        "production_evidence_candidate": spec["production_evidence_candidate"],
        "repository_head_reviewed": spec["repository_head_reviewed"],
        "head_since_production_evidence": spec["head_since_production_evidence"],
        "canonical_ledger": {
            "path": spec["canonical_ledger"],
            "file_sha256": sha256(ledger_path),
            "declared_canonical_sha256": ledger.get("canonical_sha256"),
            "requirement_count": len(requirements),
        },
        "status_inventory": dict(sorted(counts.items())),
        "retained_artifacts": retained_artifacts,
        "records": records,
    }


def markdown(register: dict) -> str:
    ledger = register["canonical_ledger"]
    lines = [
        "# Vocabulary validation evidence status register v1",
        "",
        "This is a derived execution view. It does not amend the canonical ledger, change any gate, or treat the canonical word `active` as completion. Every canonical requirement remains listed until an explicit final decision retires or supersedes it.",
        "",
        f"Production evidence candidate: `{register['production_evidence_candidate']}`. Repository head reviewed: `{register['repository_head_reviewed']}`. The commit that refreshes this derived register may follow the reviewed head but does not itself alter production behavior.",
        "",
        "Head-only changes since the production evidence candidate:",
        "",
        *[f"- {item}" for item in register["head_since_production_evidence"]],
        "",
        f"Canonical ledger: `{ledger['path']}` (`{ledger['requirement_count']}` requirements; file SHA-256 `{ledger['file_sha256']}`).",
        "",
        "The status inventory is descriptive, not a completion percentage: "
        + ", ".join(f"`{key}` {value}" for key, value in register["status_inventory"].items())
        + ".",
        "",
    ]
    lines.extend(["## Retained evidence artifact index", ""])
    for artifact in register["retained_artifacts"]:
        link = os.path.relpath(ROOT / artifact["path"], MARKDOWN_PATH.parent)
        lines.extend([
            f"### {artifact['path']}",
            "",
            f"- Artifact/checksum: [`{artifact['path']}`]({link}); SHA-256 `{artifact['sha256']}`",
            f"- Evidence class: {artifact['evidence_class']}",
            f"- Status: `{artifact['status']}`",
            f"- Interpretation: {artifact['interpretation']}",
            "",
        ])
    order = [
        "failed",
        "implemented_evidence_adverse",
        "awaiting_external_input",
        "deferred",
        "verified_current_candidate",
        "historically_measured",
        "implemented",
    ]
    labels = {
        "failed": "Failed evidence or gate",
        "implemented_evidence_adverse": "Implemented with adverse evidence",
        "awaiting_external_input": "Awaiting external input",
        "deferred": "Deferred and disabled",
        "verified_current_candidate": "Verified on the current candidate",
        "historically_measured": "Historically measured",
        "implemented": "Implemented administrative work",
    }
    register_dir = MARKDOWN_PATH.parent
    for status in order:
        records = [record for record in register["records"] if record["current_status"] == status]
        if not records:
            continue
        lines.extend([f"## {labels[status]}", ""])
        for record in records:
            artifact = record["artifact"]
            link = os.path.relpath(ROOT / artifact["path"], register_dir)
            lines.extend([
                f"### {record['id']} — {record['behavior_claim']}",
                "",
                f"- Canonical status: `{record['canonical_status']}`",
                f"- Current status: `{record['current_status']}`",
                f"- Prerequisite: {record['prerequisite']}",
                f"- Responsible capability: {record['responsible_capability']}",
                f"- Source revision/configuration: {record['source_revision_configuration']}",
                f"- Artifact/checksum: [`{artifact['path']}`]({link}); SHA-256 `{artifact['sha256']}`",
                f"- Command/environment: {record['command_environment']}",
                f"- Gate: {record['gate']}",
                f"- Evidence class: {record['evidence_class']}",
                f"- Next action: {record['next_action']}",
                f"- Decision history: {record['decision_history']}",
                "",
            ])
    lines.extend([
        "## Interpretation boundary",
        "",
        "Algorithm speed, usable UI latency, synthetic robustness, and human calibration are different evidence classes. A green schema validator, a fabricated rehearsal, or a complete implementation checklist cannot substitute for a held-out result or real learner evidence. Version-2 golden artifacts, failed/null version-3 reports, rejected selector/staged experiments, and all benchmark repetitions remain retained until a deliberate reviewed replacement is authorized.",
        "",
    ])
    return "\n".join(lines)


def encoded_outputs() -> tuple[bytes, bytes]:
    register = build()
    json_data = (json.dumps(register, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    markdown_data = markdown(register).encode("utf-8")
    return json_data, markdown_data


def write() -> None:
    json_data, markdown_data = encoded_outputs()
    JSON_PATH.write_bytes(json_data)
    MARKDOWN_PATH.write_bytes(markdown_data)
    print(f"generated {JSON_PATH.relative_to(ROOT)} and {MARKDOWN_PATH.relative_to(ROOT)}")


def check() -> None:
    json_data, markdown_data = encoded_outputs()
    for path, expected in ((JSON_PATH, json_data), (MARKDOWN_PATH, markdown_data)):
        if not path.is_file() or path.read_bytes() != expected:
            raise SystemExit(f"stale vocabulary evidence register: {path.relative_to(ROOT)}")
    print("vocabulary evidence status register is current")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    check() if args.check else write()


if __name__ == "__main__":
    main()
