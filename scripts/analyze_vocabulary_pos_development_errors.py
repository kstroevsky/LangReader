#!/usr/bin/env python3
"""Decompose POS failures using only the frozen development partition."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path


CONTENT_POS = {"noun", "verb", "adjective", "adverb"}


def summarize(rows: list[dict]) -> dict:
    weight = sum(row["occurrenceWeight"] for row in rows)
    def count(predicate) -> int:
        return sum(1 for row in rows if predicate(row))
    def mass(predicate) -> int:
        return sum(row["occurrenceWeight"] for row in rows if predicate(row))
    mechanisms = {
        "rawPOSError": lambda row: not row["rawTagCorrect"],
        "lemmaError": lambda row: not row["expectedExcluded"] and row.get("predictedLemma") != row["goldLemma"],
        "abstention": lambda row: row["abstained"],
        "abstentionRecoveredByFinalReconciliation": lambda row: row["abstained"] and row["finalIdentityCorrect"],
        "abstentionUnresolvedOrWrong": lambda row: row["abstained"] and not row["finalIdentityCorrect"],
        "nameExclusionError": lambda row: row["expectedExcluded"] != row["predictedExcluded"],
        "finalIdentityError": lambda row: not row["finalIdentityCorrect"],
    }
    return {
        "cases": len(rows),
        "occurrenceWeight": weight,
        "mechanisms": {
            name: {"cases": count(predicate), "occurrenceMass": mass(predicate)}
            for name, predicate in mechanisms.items()
        },
    }


def analyze(fixture: dict, report: dict) -> dict:
    fixture_by_id = {row["caseID"]: row for row in fixture["cases"]}
    development = [row for row in report["caseResults"] if row["evaluationSplit"] == "development"]
    if len(development) != 160 or any(fixture_by_id[row["caseID"]]["evaluationSplit"] != "development" for row in development):
        raise ValueError("analysis must contain exactly the frozen 160 development cases")
    content = [
        row for row in development
        if not row["expectedExcluded"] and row["expectedPartOfSpeech"] in CONTENT_POS
    ]
    return {
        "schemaVersion": 1,
        "sourceFixtureID": fixture["fixtureID"],
        "dataRole": "development-only-root-cause",
        "heldoutCasesReadForMetrics": 0,
        "productionThresholdsChanged": False,
        "mechanismFlagsAreOverlapping": True,
        "allDevelopment": summarize(development),
        "byLanguage": {
            language: summarize([row for row in development if row["languageCode"] == language])
            for language in ("en", "de")
        },
        "productionAssessableContentWords": summarize(content),
        "contentWordsByLanguage": {
            language: summarize([row for row in content if row["languageCode"] == language])
            for language in ("en", "de")
        },
        "rawConfusions": dict(sorted(Counter(
            f"{row['expectedPartOfSpeech']}->{row['predictedPartOfSpeech']}"
            for row in development if not row["rawTagCorrect"]
        ).items())),
        "interpretation": "Mechanism flags overlap and are diagnostic attribution, not additive causal shares. Development rows only; V2 held-out outcomes are not reused for tuning."
    }


def markdown(result: dict) -> str:
    lines = [
        "# Vocabulary POS development error decomposition",
        "",
        "This analysis uses only the 160 frozen development cases. It does not reread held-out metrics, change thresholds, or authorize a production fix. Mechanism flags overlap.",
        "",
        "| Population | Cases | Raw POS errors | Lemma errors | Abstentions | Recovered abstentions | Name exclusion errors | Final identity errors |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    populations = [("All development", result["allDevelopment"])]
    populations += [(f"{key} development", value) for key, value in result["byLanguage"].items()]
    populations.append(("Assessable content words", result["productionAssessableContentWords"]))
    populations += [(f"{key} content words", value) for key, value in result["contentWordsByLanguage"].items()]
    for label, value in populations:
        m = value["mechanisms"]
        lines.append(f"| {label} | {value['cases']} | {m['rawPOSError']['cases']} | {m['lemmaError']['cases']} | {m['abstention']['cases']} | {m['abstentionRecoveredByFinalReconciliation']['cases']} | {m['nameExclusionError']['cases']} | {m['finalIdentityError']['cases']} |")
    lines.extend(["", "Occurrence mass equals case count in this UD sample because each sampled token has unit weight; private document occurrence weighting remains unmeasured.", "", "Most useful next step: inspect development-only lemma errors, unresolved abstentions, and name-exclusion errors by language/POS before proposing any bounded change. A changed candidate requires regression tests and a fresh held-out reservation.", ""])
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("fixture", type=Path)
    parser.add_argument("report", type=Path)
    parser.add_argument("--output-json", required=True, type=Path)
    parser.add_argument("--output-markdown", required=True, type=Path)
    args = parser.parse_args()
    result = analyze(json.loads(args.fixture.read_text()), json.loads(args.report.read_text()))
    args.output_json.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    args.output_markdown.write_text(markdown(result))


if __name__ == "__main__":
    main()
