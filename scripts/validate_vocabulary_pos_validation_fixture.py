#!/usr/bin/env python3
"""Validate the frozen, deliberately unscored representative POS fixture."""

from __future__ import annotations

import argparse
import copy
import json
from collections import Counter
from pathlib import Path


def validate(fixture: dict) -> dict:
    if fixture.get("schemaVersion") != 1 or fixture.get("fixtureID") != "ud-v2.18-pos-validation-v1":
        raise ValueError("unexpected POS validation fixture version")
    if fixture.get("dataRole") != "development-and-heldout" or fixture.get("heldoutStatus") != "frozenNotScored":
        raise ValueError("held-out POS sample was not preserved as unscored")
    policy = fixture.get("selectionPolicy", {})
    if policy.get("productionThresholdsTunedFromFixture") is not False:
        raise ValueError("fixture may not authorize production threshold tuning")
    cases = fixture.get("cases", [])
    if len(cases) != 480 or len({row["caseID"] for row in cases}) != 480:
        raise ValueError("fixture must contain 480 unique cases")
    sentence_keys = {(row["sourceID"], row["sourceSentenceID"]) for row in cases}
    if len(sentence_keys) != len(cases):
        raise ValueError("fixture must select at most one token per sentence")
    expected_cells = {(language, split): 80 if split == "development" else 160 for language in ("en", "de") for split in ("development", "heldout")}
    actual_cells = Counter((row["languageCode"], row["evaluationSplit"]) for row in cases)
    if actual_cells != expected_cells:
        raise ValueError(f"language/split support changed: {dict(actual_cells)}")
    development_sentences = {(row["sourceID"], row["sourceSentenceID"]) for row in cases if row["evaluationSplit"] == "development"}
    heldout_sentences = {(row["sourceID"], row["sourceSentenceID"]) for row in cases if row["evaluationSplit"] == "heldout"}
    if development_sentences & heldout_sentences:
        raise ValueError("development and held-out sentences overlap")
    for language in ("en", "de"):
        for split in ("development", "heldout"):
            rows = [row for row in cases if row["languageCode"] == language and row["evaluationSplit"] == split]
            if len({row["goldUPOS"] for row in rows}) < 8:
                raise ValueError(f"insufficient UPOS breadth for {language}:{split}")
            if not any(row["isParticiple"] for row in rows):
                raise ValueError(f"missing participle support for {language}:{split}")
            if not any(row["goldUPOS"] == "PROPN" for row in rows):
                raise ValueError(f"missing proper-name exclusion support for {language}:{split}")
    support = fixture.get("support", {})
    if support.get("cases") != len(cases) or support.get("uniqueSentences") != len(sentence_keys):
        raise ValueError("support totals do not match cases")
    if support.get("byLanguage") != dict(sorted(Counter(row["languageCode"] for row in cases).items())):
        raise ValueError("language support summary mismatch")
    if support.get("bySplit") != dict(sorted(Counter(row["evaluationSplit"] for row in cases).items())):
        raise ValueError("split support summary mismatch")
    if support.get("byGenre") != dict(sorted(Counter(row["genre"] for row in cases).items())):
        raise ValueError("genre support summary mismatch")
    if support.get("byUPOS") != dict(sorted(Counter(row["goldUPOS"] for row in cases).items())):
        raise ValueError("UPOS support summary mismatch")
    return {"cases": len(cases), "sentences": len(sentence_keys), "languageSplitCounts": {f"{key[0]}:{key[1]}": value for key, value in sorted(actual_cells.items())}}


def self_test(fixture: dict) -> None:
    validate(fixture)
    invalid = copy.deepcopy(fixture)
    invalid["heldoutStatus"] = "scored"
    try:
        validate(invalid)
        raise AssertionError("scored held-out fixture was accepted as untouched")
    except ValueError as error:
        assert "unscored" in str(error)
    invalid = copy.deepcopy(fixture)
    invalid["cases"][1] = copy.deepcopy(invalid["cases"][0])
    try:
        validate(invalid)
        raise AssertionError("duplicate POS case was accepted")
    except ValueError:
        pass
    print("vocabulary representative POS fixture self-test passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("fixture", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    fixture = json.loads(args.fixture.read_text(encoding="utf-8"))
    self_test(fixture) if args.self_test else print(json.dumps(validate(fixture), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
