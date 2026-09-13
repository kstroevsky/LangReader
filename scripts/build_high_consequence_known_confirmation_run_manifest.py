#!/usr/bin/env python3
"""Build the evaluator manifest for the frozen high-consequence confirmation run."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESERVATION = ROOT / "docs/plans/vocabulary-validation-evidence/high-consequence-known-confirmation-manifest-v1.json"
SOURCE_REPORT = ROOT / "docs/plans/vocabulary-validation-evidence/longitudinal-compatibility-development-report-v1.json"
OUTPUT = ROOT / "docs/plans/vocabulary-validation-evidence/high-consequence-known-confirmation-evaluator-manifest-v1.json"


def encoded():
    reservation = json.loads(RESERVATION.read_text())
    source = json.loads(SOURCE_REPORT.read_text())
    manifest = dict(source["manifest"])
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
        "diagnosticHighConsequenceConfirmation": True,
        "confirmationOccasionIndex": 1,
        "decisionRule": (
            "Frozen high-consequence-known-double-confirmation-v1 feasibility only; "
            "retain all rows and do not activate production."
        ),
    })
    manifest.pop("includedRunIDs", None)
    manifest.pop("traceRunIDs", None)
    return (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    expected = encoded()
    if args.check:
        if not OUTPUT.is_file() or OUTPUT.read_bytes() != expected:
            raise SystemExit(f"stale high-consequence evaluator manifest: {OUTPUT.relative_to(ROOT)}")
        print("high-consequence confirmation evaluator manifest is current")
    else:
        OUTPUT.write_bytes(expected)
        print(f"generated {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
