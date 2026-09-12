#!/usr/bin/env python3
"""Build the evaluator manifest from the frozen compatibility reservation."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESERVATION = ROOT / "docs/plans/vocabulary-validation-evidence/longitudinal-compatibility-development-manifest-v1.json"
OUTPUT = ROOT / "docs/plans/vocabulary-validation-evidence/longitudinal-compatibility-evaluator-manifest-v1.json"


def encoded() -> bytes:
    reservation = json.loads(RESERVATION.read_text())
    source = reservation["sourceEvidence"]
    source_path = ROOT / source["report"]
    if hashlib.sha256(source_path.read_bytes()).hexdigest() != source["reportSHA256"]:
        raise ValueError("compatibility source report checksum mismatch")
    report = json.loads(source_path.read_text())
    manifest = dict(report["manifest"])
    workload = reservation["workload"]
    manifest.update({
        "seed": reservation["seed"],
        "scenarios": workload["scenarios"],
        "learnersPerScenario": workload["learnersPerScenario"],
        "historyDocumentCount": workload["historyDocumentCount"],
        "lemmaCount": workload["lemmaCount"],
        "fixedBudget": workload["fixedBudget"],
        "targetCoverage": workload["targetCoverage"],
        "timingRepetitions": 1,
        "decisionRule": (
            "Retain all frozen rows. Evaluate paired-validation-evidence-log-likelihood-ratio-v1 "
            "at threshold zero without tuning; production behavior remains unchanged."
        ),
    })
    return (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    expected = encoded()
    if args.check:
        if not OUTPUT.is_file() or OUTPUT.read_bytes() != expected:
            raise SystemExit(f"stale compatibility evaluator manifest: {OUTPUT.relative_to(ROOT)}")
        print("vocabulary compatibility evaluator manifest is current")
    else:
        OUTPUT.write_bytes(expected)
        print(f"generated {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
