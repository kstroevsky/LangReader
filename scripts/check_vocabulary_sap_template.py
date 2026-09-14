#!/usr/bin/env python3
"""Keep the confirmatory SAP template explicit, incomplete, and unapproved."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SAP_PATH = ROOT / "docs/research/VOCABULARY_VALIDATION_SAP_TEMPLATE.md"

REQUIRED_TEXT = [
    "## Sample size and precision planning to freeze",
    "Planned participants by language, proficiency stratum, L1 stratum",
    "Planned independent documents and near-duplicate groups",
    "Anticipated participant, document, item, and repeated-item cluster sizes",
    "Expected audited selected-card support and unselected final-tail support",
    "Minimum expected nonzero inclusion probability",
    "Maximum expected design weight",
    "Expected effective sample size overall and for each primary/subgroup",
    "Desired interval precision for calibration, deck precision/recall, realized",
    "Warm non-inferiority margin",
    "Independent learners per lexical item for calibration-pack eligibility",
    "## Blocking study-design decisions to freeze",
    "Pretest-interference evidence or randomized/order/carryover design",
    "Meaning prompt, hidden target-sense/context mapping, ambiguity status",
    "Human theta-interval endpoint decision and independent latent reference",
    "does not invent a participant count, precision target, non-inferiority margin",
]


def validate(text: str) -> None:
    missing = [required for required in REQUIRED_TEXT if required not in text]
    if missing:
        raise ValueError(f"SAP template is missing required planning fields: {missing}")
    if re.search(r"^- \[[xX]\]", text, flags=re.MULTILINE):
        raise ValueError("SAP template must not claim an approval checkbox is complete")
    if "not a completed Statistical Analysis" not in text:
        raise ValueError("SAP template no longer states that it is incomplete")


def self_test() -> None:
    text = SAP_PATH.read_text(encoding="utf-8")
    validate(text)
    try:
        validate(text.replace(REQUIRED_TEXT[5], "removed inclusion field", 1))
        raise AssertionError("missing precision field was accepted")
    except ValueError as error:
        assert "missing required planning fields" in str(error)
    try:
        validate(text.replace("- [ ] The estimands", "- [x] The estimands", 1))
        raise AssertionError("pre-approved SAP checkbox was accepted")
    except ValueError as error:
        assert "must not claim" in str(error)
    print("vocabulary SAP template readiness self-test passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    text = SAP_PATH.read_text(encoding="utf-8")
    self_test() if args.self_test else validate(text)


if __name__ == "__main__":
    main()
