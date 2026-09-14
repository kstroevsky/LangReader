#!/usr/bin/env python3
"""Validate and summarize the frozen representative POS report."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from collections import Counter, defaultdict
from pathlib import Path


def close(actual: float, expected: float) -> bool:
    return math.isfinite(actual) and math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12)


def metrics(rows: list[dict]) -> dict:
    count = len(rows)
    weight = sum(row["occurrenceWeight"] for row in rows)
    return {
        "caseCount": count,
        "occurrenceWeight": weight,
        "rawTagAccuracy": sum(row["rawTagCorrect"] for row in rows) / count,
        "abstentionRate": sum(row["abstained"] for row in rows) / count,
        "finalIdentityAccuracy": sum(row["finalIdentityCorrect"] for row in rows) / count,
        "occurrenceWeightedFinalIdentityAccuracy": sum(
            row["occurrenceWeight"] for row in rows if row["finalIdentityCorrect"]
        ) / weight,
    }


def split_merge(rows: list[dict]) -> dict:
    gold = {
        f"{row['languageCode']}|{row['goldLemma']}|{row['expectedPartOfSpeech']}"
        for row in rows if not row["expectedExcluded"]
    }
    predicted = {
        f"{row['languageCode']}|{row['predictedLemma']}|{row['predictedPartOfSpeech']}"
        for row in rows if not row["predictedExcluded"] and row["predictedLemma"] is not None
    }
    def by_lemma(identities: set[str]) -> dict[str, set[str]]:
        result = defaultdict(set)
        for identity in identities:
            language, lemma, part = identity.split("|", 2)
            result[f"{language}|{lemma}"].add(part)
        return result
    gold_by_lemma = by_lemma(gold)
    predicted_by_lemma = by_lemma(predicted)
    lemmas = set(gold_by_lemma) | set(predicted_by_lemma)
    return {
        "goldIdentityCount": len(gold),
        "predictedIdentityCount": len(predicted),
        "missingGoldIdentityCount": len(gold - predicted),
        "extraPredictedIdentityCount": len(predicted - gold),
        "lemmaPOSSetMismatchCount": sum(gold_by_lemma[key] != predicted_by_lemma[key] for key in lemmas),
    }


def validate(fixture: dict, fixture_bytes: bytes, report: dict) -> dict:
    if fixture.get("fixtureID") != "ud-v2.18-pos-validation-v2" or fixture.get("heldoutStatus") != "frozenNotScored":
        raise ValueError("unexpected or non-frozen validation fixture")
    if report.get("schemaVersion") != 1 or report.get("fixtureID") != fixture["fixtureID"]:
        raise ValueError("report fixture/schema identity mismatch")
    if report.get("fixtureSHA256") != hashlib.sha256(fixture_bytes).hexdigest():
        raise ValueError("report fixture checksum mismatch")
    if report.get("policy") != {"minimumLeadingProbability": 0.65, "minimumMargin": 0.2}:
        raise ValueError("production POS thresholds changed")
    cases = {row["caseID"]: row for row in fixture["cases"]}
    results = report.get("caseResults", [])
    if len(results) != 480 or len({row["caseID"] for row in results}) != 480 or set(cases) != {row["caseID"] for row in results}:
        raise ValueError("report does not cover every frozen case exactly once")
    for row in results:
        source = cases[row["caseID"]]
        for field in ("sourceID", "sourceSentenceID", "languageCode", "evaluationSplit", "genre", "occurrenceWeight"):
            if row[field] != source[field]:
                raise ValueError(f"case join mismatch for {row['caseID']}:{field}")
        if row["isParticiple"] != source["isParticiple"]:
            raise ValueError("participle join mismatch")
        if row["abstained"] != (row["predictedPartOfSpeech"] == "unknown"):
            raise ValueError("abstention flag mismatch")
        if not math.isfinite(row["leadingProbability"]) or not math.isfinite(row["margin"]):
            raise ValueError("non-finite confidence")

    overall = metrics(results)
    for field in ("rawTagAccuracy", "abstentionRate", "finalIdentityAccuracy", "occurrenceWeightedFinalIdentityAccuracy"):
        if not close(report[field], overall[field]):
            raise ValueError(f"overall metric mismatch: {field}")

    dimensions = {
        "evaluationSplit": lambda row: row["evaluationSplit"],
        "language": lambda row: row["languageCode"],
        "languageAndSplit": lambda row: f"{row['languageCode']}:{row['evaluationSplit']}",
        "genre": lambda row: row["genre"],
        "expectedPartOfSpeech": lambda row: row["expectedPartOfSpeech"],
        "languageSplitAndExpectedPartOfSpeech": lambda row: f"{row['languageCode']}:{row['evaluationSplit']}:{row['expectedPartOfSpeech']}",
        "participle": lambda row: "participle" if row["isParticiple"] else "other",
    }
    expected_groups = {}
    for dimension, key in dimensions.items():
        for value in sorted({key(row) for row in results}):
            expected_groups[(dimension, value)] = metrics([row for row in results if key(row) == value])
    actual_groups = {(row["dimension"], row["value"]): row for row in report.get("groupMetrics", [])}
    if set(actual_groups) != set(expected_groups):
        raise ValueError("group metric coverage mismatch")
    for key, expected in expected_groups.items():
        actual = actual_groups[key]
        for field, value in expected.items():
            if isinstance(value, float):
                if not close(actual[field], value):
                    raise ValueError(f"group metric mismatch: {key}:{field}")
            elif actual[field] != value:
                raise ValueError(f"group support mismatch: {key}:{field}")

    expected_split_merge = {}
    for split in ("development", "heldout"):
        for language in ("en", "de"):
            expected_split_merge[(split, language)] = split_merge([
                row for row in results if row["evaluationSplit"] == split and row["languageCode"] == language
            ])
    actual_split_merge = {(row["evaluationSplit"], row["languageCode"]): row for row in report.get("splitMergeSummaries", [])}
    if set(actual_split_merge) != set(expected_split_merge):
        raise ValueError("split/merge summary coverage mismatch")
    for key, expected in expected_split_merge.items():
        if any(actual_split_merge[key][field] != value for field, value in expected.items()):
            raise ValueError(f"split/merge summary mismatch: {key}")

    split_consequences = report.get("splitConsequences", [])
    if {(row["evaluationSplit"], row["consequence"]["languageCode"]) for row in split_consequences} != set(expected_split_merge):
        raise ValueError("split consequence coverage mismatch")
    for row in split_consequences:
        split = row["evaluationSplit"]
        consequence = row["consequence"]
        language = consequence["languageCode"]
        cell = [item for item in results if item["evaluationSplit"] == split and item["languageCode"] == language]
        gold = sum(item["occurrenceWeight"] for item in cell if not item["expectedExcluded"])
        predicted = sum(item["occurrenceWeight"] for item in cell if not item["predictedExcluded"])
        if consequence["goldOccurrenceDenominator"] != gold or consequence["predictedOccurrenceDenominator"] != predicted:
            raise ValueError("split consequence denominator mismatch")
        if consequence["denominatorDelta"] != predicted - gold:
            raise ValueError("split consequence denominator delta mismatch")
        if consequence["selectedDeckSymmetricDifferenceCount"] != len(set(consequence["goldSelectedKeys"]) ^ set(consequence["predictedSelectedKeys"])):
            raise ValueError("split consequence deck difference mismatch")

    return {
        "fixtureID": fixture["fixtureID"],
        "cases": len(results),
        "developmentCases": sum(row["evaluationSplit"] == "development" for row in results),
        "heldoutCases": sum(row["evaluationSplit"] == "heldout" for row in results),
        "rawTagAccuracy": report["rawTagAccuracy"],
        "abstentionRate": report["abstentionRate"],
        "finalIdentityAccuracy": report["finalIdentityAccuracy"],
    }


def percent(value: float) -> str:
    return f"{value * 100:.2f}%"


def markdown(report: dict) -> str:
    metrics_by_key = {(row["dimension"], row["value"]): row for row in report["groupMetrics"]}
    lines = [
        "# Vocabulary POS validation report v2",
        "",
        "Status: completed adverse engineering evidence; representative release validation remains incomplete.",
        "",
        f"Frozen fixture: `{report['fixtureID']}`; SHA-256 `{report['fixtureSHA256']}`. Runtime: {report['environment']['os']}.",
        "",
        "The production 0.65 leading-probability and 0.20 margin thresholds were unchanged. No result in this report authorizes threshold tuning or a POS release claim.",
        "",
        "## Overall",
        "",
        "| Cases | Raw mapped-POS accuracy | Abstention | Final lexical-identity accuracy |",
        "| ---: | ---: | ---: | ---: |",
        f"| {len(report['caseResults'])} | {percent(report['rawTagAccuracy'])} | {percent(report['abstentionRate'])} | {percent(report['finalIdentityAccuracy'])} |",
        "",
        "## Development and held-out results",
        "",
        "| Cell | Cases | Raw POS | Abstention | Final identity |",
        "| --- | ---: | ---: | ---: | ---: |",
    ]
    for value in ("en:development", "en:heldout", "de:development", "de:heldout"):
        row = metrics_by_key[("languageAndSplit", value)]
        lines.append(f"| {value} | {row['caseCount']} | {percent(row['rawTagAccuracy'])} | {percent(row['abstentionRate'])} | {percent(row['finalIdentityAccuracy'])} |")
    lines.extend(["", "## Genre/source strata", "", "| Genre/source | Cases | Raw POS | Abstention | Final identity |", "| --- | ---: | ---: | ---: | ---: |"])
    for key in sorted(value for dimension, value in metrics_by_key if dimension == "genre"):
        row = metrics_by_key[("genre", key)]
        lines.append(f"| {key} | {row['caseCount']} | {percent(row['rawTagAccuracy'])} | {percent(row['abstentionRate'])} | {percent(row['finalIdentityAccuracy'])} |")
    lines.extend(["", "## Split merge and downstream consequences", "", "| Split/language | Missing gold identities | Extra predicted identities | Lemma POS-set mismatches | Denominator delta | Erroneous excluded/included mass | First question changed | Deck symmetric difference |", "| --- | ---: | ---: | ---: | ---: | ---: | --- | ---: |"])
    consequences = {(row["evaluationSplit"], row["consequence"]["languageCode"]): row["consequence"] for row in report["splitConsequences"]}
    for row in report["splitMergeSummaries"]:
        key = (row["evaluationSplit"], row["languageCode"])
        consequence = consequences[key]
        lines.append(
            f"| {key[0]}:{key[1]} | {row['missingGoldIdentityCount']} | {row['extraPredictedIdentityCount']} | {row['lemmaPOSSetMismatchCount']} | {consequence['denominatorDelta']} | {consequence['erroneousExcludedMass']}/{consequence['erroneousIncludedMass']} | {'yes' if consequence['questionIdentityChanged'] else 'no'} | {consequence['selectedDeckSymmetricDifferenceCount']} |"
        )
    lines.extend([
        "",
        "## Interpretation",
        "",
        "The dev and held-out directions are similar, so this larger run confirms that the eight-token warning was not merely a micro-fixture artifact. The results are adverse: final identity remains materially below raw POS accuracy, German is weaker than English, two of four split/language cells change the first question, and every cell has many selected-deck identity differences.",
        "",
        "This is still UD token/sentence evidence rather than representative private PDF/EPUB/DOCX documents or real learner evidence. English has five EWT genres; German GSD exposes one mixed-web source stratum. Upstream lemma limitations, OS-dependent NaturalLanguage behavior, target-token alignment, and corpus/domain coverage remain explicit limitations.",
        "",
    ])
    return "\n".join(lines)


def self_test(fixture: dict, fixture_bytes: bytes, report: dict) -> None:
    validate(fixture, fixture_bytes, report)
    invalid = copy.deepcopy(report)
    invalid["policy"]["minimumMargin"] = 0.19
    try:
        validate(fixture, fixture_bytes, invalid)
        raise AssertionError("changed production threshold was accepted")
    except ValueError as error:
        assert "thresholds changed" in str(error)
    invalid = copy.deepcopy(report)
    invalid["groupMetrics"][0]["caseCount"] += 1
    try:
        validate(fixture, fixture_bytes, invalid)
        raise AssertionError("corrupted group support was accepted")
    except ValueError as error:
        assert "group support mismatch" in str(error)
    print("vocabulary representative POS report self-test passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("fixture", type=Path)
    parser.add_argument("report", type=Path)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--output-markdown", type=Path)
    args = parser.parse_args()
    fixture_bytes = args.fixture.read_bytes()
    fixture = json.loads(fixture_bytes)
    report = json.loads(args.report.read_text(encoding="utf-8"))
    summary = validate(fixture, fixture_bytes, report)
    if args.self_test:
        self_test(fixture, fixture_bytes, report)
    if args.output_markdown:
        args.output_markdown.write_text(markdown(report), encoding="utf-8")
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
