#!/usr/bin/env python3
"""Validate the pinned vocabulary POS diagnostic report."""

from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path


def require(value, message):
    if not value:
        raise ValueError(message)


def validate(fixture, report):
    require(fixture["schemaVersion"] == 1 and fixture["release"] == "UD 2.18", "fixture version")
    require(report["schemaVersion"] == 1 and report["fixtureRelease"] == fixture["release"], "report version")
    require(report["policy"] == {"minimumLeadingProbability": 0.65, "minimumMargin": 0.2}, "production thresholds changed")
    fixture_by_id = {row["caseID"]: row for row in fixture["cases"]}
    results = report["caseResults"]
    require(len(results) == len(fixture_by_id) and len({row["caseID"] for row in results}) == len(results), "case coverage")
    for row in results:
        source = fixture_by_id.get(row["caseID"])
        require(source is not None, "unknown case")
        require(row["sourceSentenceID"] == source["sourceSentenceID"] and row["occurrenceWeight"] == source["occurrenceWeight"], "case join")
        require(math.isfinite(row["leadingProbability"]) and math.isfinite(row["margin"]), "non-finite confidence")
        require(row["abstained"] == (row["predictedPartOfSpeech"] == "unknown"), "abstention mismatch")
    count = len(results)
    weight = sum(row["occurrenceWeight"] for row in results)
    require(math.isclose(report["rawTagAccuracy"], sum(row["rawTagCorrect"] for row in results) / count), "raw accuracy")
    require(math.isclose(report["abstentionRate"], sum(row["abstained"] for row in results) / count), "abstention")
    require(math.isclose(report["finalIdentityAccuracy"], sum(row["finalIdentityCorrect"] for row in results) / count), "identity accuracy")
    require(math.isclose(report["occurrenceWeightedFinalIdentityAccuracy"], sum(row["occurrenceWeight"] for row in results if row["finalIdentityCorrect"]) / weight), "weighted identity")
    require(any("VerbForm=Part" in row["goldFeatures"] and row["languageCode"] == "en" for row in results), "English participle missing")
    require(any("VerbForm=Part" in row["goldFeatures"] and row["languageCode"] == "de" for row in results), "German participle missing")
    for consequence in report["consequences"]:
        rows = [row for row in results if row["languageCode"] == consequence["languageCode"]]
        gold = sum(row["occurrenceWeight"] for row in rows if not row["expectedExcluded"])
        predicted = sum(row["occurrenceWeight"] for row in rows if not row["predictedExcluded"])
        require(consequence["goldOccurrenceDenominator"] == gold, "gold denominator")
        require(consequence["predictedOccurrenceDenominator"] == predicted, "predicted denominator")
        require(consequence["denominatorDelta"] == predicted - gold, "denominator delta")
        expected_diff = len(set(consequence["goldSelectedKeys"]) ^ set(consequence["predictedSelectedKeys"]))
        require(consequence["selectedDeckSymmetricDifferenceCount"] == expected_diff, "deck difference")


def self_test(fixture, report):
    validate(fixture, report)
    for mutation in ("metric", "denominator"):
        invalid = copy.deepcopy(report)
        if mutation == "metric": invalid["rawTagAccuracy"] = 1
        else: invalid["consequences"][0]["goldOccurrenceDenominator"] += 1
        try:
            validate(fixture, invalid)
        except ValueError:
            continue
        raise AssertionError("invalid POS report passed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("fixture", type=Path)
    parser.add_argument("report", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    fixture = json.loads(args.fixture.read_text())
    report = json.loads(args.report.read_text())
    self_test(fixture, report) if args.self_test else validate(fixture, report)
    print("vocabulary POS report valid")


if __name__ == "__main__": main()
