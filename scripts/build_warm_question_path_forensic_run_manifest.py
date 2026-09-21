#!/usr/bin/env python3
"""Build the selected-run longitudinal evaluator manifest for warm forensics."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESERVATION = ROOT / "docs/plans/vocabulary-validation-evidence/warm-question-path-forensic-manifest-v1.json"
OUTPUT = ROOT / "docs/plans/vocabulary-validation-evidence/warm-question-path-forensic-evaluator-manifest-v1.json"


def encoded():
    reservation = json.loads(RESERVATION.read_text())
    source = reservation["sourceEvidence"]
    source_path = ROOT / source["report"]
    if hashlib.sha256(source_path.read_bytes()).hexdigest() != source["reportSHA256"]:
        raise ValueError("forensic source report checksum mismatch")
    report = json.loads(source_path.read_text())
    manifest = dict(report["manifest"])
    run_ids = reservation["selectionRule"]["selectedRunIDs"]
    manifest.update({
        "scenarios": sorted({run_id.split(":learner-", 1)[0] for run_id in run_ids}),
        "includedRunIDs": run_ids,
        "traceRunIDs": run_ids,
        "timingRepetitions": 1,
        "decisionRule": (
            "Selected-case mechanism trace from warm-question-path-forensic-manifest-v1; "
            "no population claim, threshold selection, or production change."
        ),
    })
    return (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    expected = encoded()
    if args.check:
        if not OUTPUT.is_file() or OUTPUT.read_bytes() != expected:
            raise SystemExit(f"stale forensic evaluator manifest: {OUTPUT.relative_to(ROOT)}")
        print("warm question-path forensic evaluator manifest is current")
    else:
        OUTPUT.write_bytes(expected)
        print(f"generated {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
