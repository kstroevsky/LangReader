#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

from run_representative_book_checkpoint_exports import harness_sha256


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_frozen_rules(rules: dict) -> None:
    if rules.get("analysisStatus") != "frozen":
        raise ValueError("analysis rules are not frozen")
    bootstrap = rules.get("bootstrap", {})
    if bootstrap.get("cluster") != "workFamilyID":
        raise ValueError("bootstrap cluster must remain workFamilyID")
    if not isinstance(bootstrap.get("replicates"), int) or bootstrap["replicates"] <= 0:
        raise ValueError("bootstrap replicate count must be a positive frozen integer")
    margins = rules.get("nonInferiorityMargins", {})
    for name, value in margins.items():
        if not isinstance(value, (int, float)):
            raise ValueError(f"non-inferiority margin {name} is not frozen")
    for field in (
        "plannedStratification",
        "missingDataPolicy",
        "stoppingEnrollmentRule",
        "retryPolicy",
    ):
        value = rules.get(field)
        if value in (None, "", [], {}):
            raise ValueError(f"analysis rules are missing frozen {field}")
    stopping = rules.get("stoppingEnrollmentRule", {})
    target = stopping.get("automaticSplitAdequacyTarget") if isinstance(stopping, dict) else None
    if not isinstance(target, int) or target <= 0:
        raise ValueError("stopping/enrollment rule must freeze a positive automatic-split adequacy target")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus-manifest", type=Path, required=True)
    parser.add_argument("--holdout-manifest", type=Path, required=True)
    parser.add_argument("--gold-manifest", type=Path, required=True)
    parser.add_argument("--analysis-rules", type=Path, required=True)
    parser.add_argument(
        "--analysis-code",
        type=Path,
        default=Path(__file__).resolve().with_name("analyze_representative_book_checkpoints.py"),
    )
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    corpus = json.loads(args.corpus_manifest.read_text(encoding="utf-8"))
    holdout = json.loads(args.holdout_manifest.read_text(encoding="utf-8"))
    gold = json.loads(args.gold_manifest.read_text(encoding="utf-8"))
    rules = json.loads(args.analysis_rules.read_text(encoding="utf-8"))
    require_frozen_rules(rules)

    if gold.get("status") != "frozen" or gold.get("dataRole") != "confirmatory":
        raise ValueError("confirmatory gold manifest must be frozen")
    if gold.get("panel") != "representative":
        raise ValueError("confirmatory gold manifest must use the representative panel")
    if gold.get("checkpoints") != corpus.get("checkpoints"):
        raise ValueError("gold manifest checkpoint provenance differs from corpus")
    if holdout.get("checkpoints") != corpus.get("checkpoints"):
        raise ValueError("holdout checkpoint provenance differs from corpus")
    expected_sampling_policy = corpus.get("samplingPolicies", {}).get("representative")
    if holdout.get("samplingPolicy") != expected_sampling_policy:
        raise ValueError("holdout sampling policy differs from the frozen representative policy")
    for row in gold.get("documents", []):
        if row.get("candidateSelectionPolicyVersion") != expected_sampling_policy:
            raise ValueError(
                f"gold document {row.get('documentID')} does not use the frozen representative policy"
            )
        if row.get("unreviewedOccurrenceCount") != 0:
            raise ValueError(f"gold document {row.get('documentID')} still has unreviewed occurrences")

    corpus_confirmatory = {
        row["documentID"]: row["sourceSHA256"]
        for row in corpus.get("documents", [])
        if row.get("dataRole") == "confirmatory"
    }
    holdout_documents = {
        row["documentID"]: row["sourceSHA256"] for row in holdout.get("documents", [])
    }
    gold_documents = {
        row["documentID"]: row["sourceSHA256"] for row in gold.get("documents", [])
    }
    if holdout_documents != corpus_confirmatory:
        raise ValueError("holdout document set differs from the frozen confirmatory corpus")
    if gold_documents != corpus_confirmatory:
        raise ValueError("frozen gold does not cover the complete confirmatory corpus")

    output = {
        "schemaVersion": 1,
        "status": "frozen",
        "protocolVersion": corpus.get("protocolVersion"),
        "frozenAtUTC": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "checkpoints": corpus["checkpoints"],
        "documentIDs": sorted(corpus_confirmatory),
        "documents": [
            {
                "documentID": row["documentID"],
                "sourceSHA256": row["sourceSHA256"],
                "annotationSHA256": row["annotationSHA256"],
                "sampledTextSHA256": row["sampledTextSHA256"],
            }
            for row in sorted(gold["documents"], key=lambda value: value["documentID"])
        ],
        "goldPanel": gold["panel"],
        "samplingPolicy": holdout["samplingPolicy"],
        "corpusManifestSHA256": sha256_file(args.corpus_manifest),
        "holdoutManifestSHA256": sha256_file(args.holdout_manifest),
        "goldManifestSHA256": sha256_file(args.gold_manifest),
        "analysisRulesSHA256": sha256_file(args.analysis_rules),
        "analysisCodeSHA256": sha256_file(args.analysis_code),
        "checkpointExportHarnessSHA256": {
            checkpoint: harness_sha256(Path(__file__).resolve().parents[1], checkpoint)
            for checkpoint in ("A", "B", "C")
        },
        "bootstrapReplicates": rules["bootstrap"]["replicates"],
        "bootstrapCluster": rules["bootstrap"]["cluster"],
        "plannedStratification": rules["plannedStratification"],
        "missingDataPolicy": rules["missingDataPolicy"],
        "stoppingEnrollmentRule": rules["stoppingEnrollmentRule"],
        "retryPolicy": rules["retryPolicy"],
        "requiredConfirmatoryChecks": rules.get("requiredConfirmatoryChecks", []),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote frozen confirmatory experiment record: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
