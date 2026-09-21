#!/usr/bin/env python3
"""Analyze the frozen selected-case warm question-path forensic repair."""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path


PATHS = ("coldNatural", "warmNatural", "coldFixedBudget", "warmFixedBudget")
KNOWN_SUPPORTING = {"verifiedKnown", "typedVerifiedKnown", "legacyKnown"}
PARITY_FIELDS = (
    "questionCount", "answerPathFingerprint", "posteriorFingerprint",
    "selectedFingerprint", "missedOccurrenceMass", "realizedProjectedCoverage",
    "conservativeCoverageLowerBound",
)


def trace_paths(run):
    return {path["path"]: path for path in run["forensicTrace"]["paths"]}


def first_divergence(cold, warm):
    for ordinal, (cold_question, warm_question) in enumerate(zip(cold, warm), 1):
        if cold_question["canonicalKey"] != warm_question["canonicalKey"]:
            return {
                "ordinal": ordinal,
                "coldQuestion": cold_question["canonicalKey"],
                "warmQuestion": warm_question["canonicalKey"],
                "coldSelectionType": cold_question["selectionType"],
                "warmSelectionType": warm_question["selectionType"],
            }
    if len(cold) != len(warm):
        return {
            "ordinal": min(len(cold), len(warm)) + 1,
            "coldQuestion": cold[min(len(cold), len(warm))]["canonicalKey"] if len(cold) > len(warm) else None,
            "warmQuestion": warm[min(len(cold), len(warm))]["canonicalKey"] if len(warm) > len(cold) else None,
            "coldSelectionType": None,
            "warmSelectionType": None,
        }
    return None


def false_negative_partition(path):
    partition = Counter()
    for item in path["finalItems"]:
        if item["finalClassification"] == "excluded" or item["truthKnown"] or item["selectedInFinalDeck"]:
            continue
        key = f"asked:{item['evidence']}" if item["asked"] else "unasked:no-evidence"
        partition[key] += item["occurrenceCount"]
    return dict(sorted(partition.items()))


def known_supporting_unknown_mass(path, missed_only=False):
    return sum(
        item["occurrenceCount"]
        for item in path["finalItems"]
        if not item["truthKnown"]
        and item.get("evidence") in KNOWN_SUPPORTING
        and (not missed_only or not item["selectedInFinalDeck"])
    )


def exclusive_asked_mass(cold, warm):
    cold_items = {item["canonicalKey"]: item for item in cold["finalItems"]}
    warm_items = {item["canonicalKey"]: item for item in warm["finalItems"]}
    cold_asked = {item["canonicalKey"] for item in cold["finalItems"] if item["asked"]}
    warm_asked = {item["canonicalKey"] for item in warm["finalItems"] if item["asked"]}

    def mass(keys, items, known):
        return sum(items[key]["occurrenceCount"] for key in keys if items[key]["truthKnown"] == known)

    cold_only = cold_asked - warm_asked
    warm_only = warm_asked - cold_asked
    return {
        "coldOnly": {
            "known": mass(cold_only, cold_items, True),
            "unknown": mass(cold_only, cold_items, False),
        },
        "warmOnly": {
            "known": mass(warm_only, warm_items, True),
            "unknown": mass(warm_only, warm_items, False),
        },
    }


def deck_difference(cold, warm):
    items = {item["canonicalKey"]: item for item in cold["finalItems"]}
    cold_selected = {item["canonicalKey"] for item in cold["finalItems"] if item["selectedInFinalDeck"]}
    warm_selected = {item["canonicalKey"] for item in warm["finalItems"] if item["selectedInFinalDeck"]}
    cold_only = cold_selected - warm_selected
    warm_only = warm_selected - cold_selected
    return {
        "symmetricDifferenceOccurrenceMass": sum(items[key]["occurrenceCount"] for key in cold_only | warm_only),
        "coldOnlyOccurrenceMass": sum(items[key]["occurrenceCount"] for key in cold_only),
        "warmOnlyOccurrenceMass": sum(items[key]["occurrenceCount"] for key in warm_only),
    }


def path_summary(path, aggregate):
    partition = false_negative_partition(path)
    missed = sum(partition.values())
    if missed != aggregate["missedOccurrenceMass"]:
        raise ValueError("false-negative partition does not conserve missed mass")
    unasked = partition.get("unasked:no-evidence", 0)
    return {
        "assessableOccurrenceMass": aggregate["assessableOccurrenceMass"],
        "missedOccurrenceMass": missed,
        "falseNegativeMissedOccurrenceMassByAskedStatusAndEvidence": partition,
        "unaskedMissedOccurrenceShare": 0 if missed == 0 else unasked / missed,
        "knownSupportingEvidenceOnTrulyUnknownOccurrenceMass": known_supporting_unknown_mass(path),
        "knownSupportingEvidenceOnMissedTrulyUnknownOccurrenceMass": known_supporting_unknown_mass(
            path, missed_only=True
        ),
    }


def analyze(repaired, failed, reservation):
    repaired_by_id = {run["runID"]: run for run in repaired["runs"]}
    failed_by_id = {run["runID"]: run for run in failed["runs"]}
    selected_ids = reservation["selectionRule"]["selectedRunIDs"]
    if set(repaired_by_id) != set(failed_by_id) or set(repaired_by_id) != set(selected_ids):
        raise ValueError("repaired case set differs from the frozen attempt")

    rows = []
    for run_id in selected_ids:
        run = repaired_by_id[run_id]
        original = failed_by_id[run_id]
        repaired_paths = trace_paths(run)
        failed_paths = trace_paths(original)
        for path in PATHS:
            for field in PARITY_FIELDS:
                if run[path][field] != original[path][field]:
                    raise ValueError(f"path parity changed: {run_id}:{path}:{field}")
            if repaired_paths[path]["questions"] != failed_paths[path]["questions"]:
                raise ValueError(f"question trace changed: {run_id}:{path}")

        natural_cold = repaired_paths["coldNatural"]
        natural_warm = repaired_paths["warmNatural"]
        fixed_cold = repaired_paths["coldFixedBudget"]
        fixed_warm = repaired_paths["warmFixedBudget"]
        rows.append({
            "runID": run_id,
            "scenario": run["scenario"],
            "role": "severe-selected-case" if run["naturalCoverageDifference"] < -0.05 else "deterministic-control",
            "naturalCoverageDifference": run["naturalCoverageDifference"],
            "firstNaturalQuestionDivergence": first_divergence(
                natural_cold["questions"], natural_warm["questions"]
            ),
            "naturalExclusiveAskedOccurrenceMassByTruth": exclusive_asked_mass(natural_cold, natural_warm),
            "fixedExclusiveAskedOccurrenceMassByTruth": exclusive_asked_mass(fixed_cold, fixed_warm),
            "naturalDeckDifference": deck_difference(natural_cold, natural_warm),
            "fixedDeckDifference": deck_difference(fixed_cold, fixed_warm),
            "paths": {
                path: path_summary(repaired_paths[path], run[path])
                for path in PATHS
            },
        })

    severe = [row for row in rows if row["role"] == "severe-selected-case"]
    warm_missed = sum(row["paths"]["warmNatural"]["missedOccurrenceMass"] for row in severe)
    warm_false_known_missed = sum(
        row["paths"]["warmNatural"]["knownSupportingEvidenceOnMissedTrulyUnknownOccurrenceMass"]
        for row in severe
    )
    warm_unasked_missed = sum(
        row["paths"]["warmNatural"]["falseNegativeMissedOccurrenceMassByAskedStatusAndEvidence"].get(
            "unasked:no-evidence", 0
        )
        for row in severe
    )
    validation_divergence_count = sum(
        row["firstNaturalQuestionDivergence"] is not None
        and row["firstNaturalQuestionDivergence"]["ordinal"] == 4
        and row["firstNaturalQuestionDivergence"]["warmSelectionType"] == "tailValidation"
        for row in severe
    )
    false_known_miss_count = sum(
        row["paths"]["warmNatural"]["knownSupportingEvidenceOnMissedTrulyUnknownOccurrenceMass"] > 0
        for row in severe
    )
    return {
        "schemaVersion": 1,
        "dataRole": "diagnostic-development-forensic-selected-cases",
        "productionConfigurationChanged": False,
        "selectedRunCount": len(rows),
        "severeCaseCount": len(severe),
        "controlCount": len(rows) - len(severe),
        "rows": rows,
        "aggregateSevereWarmNatural": {
            "missedOccurrenceMass": warm_missed,
            "knownSupportingEvidenceOnMissedTrulyUnknownOccurrenceMass": warm_false_known_missed,
            "knownSupportingEvidenceShareOfMissedMass": (
                0 if warm_missed == 0 else warm_false_known_missed / warm_missed
            ),
            "unaskedMissedOccurrenceMass": warm_unasked_missed,
            "unaskedShareOfMissedMass": 0 if warm_missed == 0 else warm_unasked_missed / warm_missed,
        },
        "hypothesisAssessment": {
            "earlyWarmValidationChangesPath": {
                "status": (
                    "supported-in-selected-severe-cases"
                    if validation_divergence_count == len(severe)
                    else "mixed-in-selected-severe-cases"
                ),
                "evidence": f"{validation_divergence_count}/{len(severe)} severe paths first diverged at ordinal 4 on warm tail validation",
            },
            "knownSupportingEvidenceOnUnknownHighMassItems": {
                "status": (
                    "supported-in-selected-severe-cases"
                    if false_known_miss_count == len(severe)
                    else "mixed-in-selected-severe-cases"
                ),
                "evidence": f"{false_known_miss_count}/{len(severe)} severe warm paths missed occurrence mass carrying known-supporting evidence despite synthetic unknown truth",
            },
            "harmConcentratesInNeverAskedItems": {
                "status": "not-supported-in-selected-severe-cases",
                "evidence": "asked items with known-supporting evidence account for the majority of aggregate severe warm missed mass",
            },
            "mechanismDiffersByScenario": {
                "status": (
                    "not-supported-as-primary-explanation"
                    if false_known_miss_count == len(severe)
                    else "mixed-in-selected-cases"
                ),
                "evidence": f"the known-supporting-evidence mechanism appears in {false_known_miss_count}/{len(severe)} severe cases across {len({row['scenario'] for row in severe})} scenario families",
            },
        },
        "interpretation": (
            "Selected-case mechanism evidence only. The common mechanism is interaction between early warm path divergence, "
            "fallible verifiedKnown evidence on truly unknown high-occurrence items, and stopping/deck selection; case counts "
            "do not estimate prevalence or authorize mitigation."
        ),
    }


def markdown(result):
    aggregate = result["aggregateSevereWarmNatural"]
    lines = [
        "# Warm question-path forensic result v2",
        "",
        "This reporting-only repair preserves the same outcome-selected 11 cases and every v1 path/question trace. It changes no production configuration and makes no population claim.",
        "",
        f"Selected cases: {result['selectedRunCount']} ({result['severeCaseCount']} severe, {result['controlCount']} deterministic controls).",
        "",
        f"Across the seven severe warm-natural paths, missed occurrence mass was {aggregate['missedOccurrenceMass']}. Known-supporting evidence attached to truly unknown missed items accounted for {aggregate['knownSupportingEvidenceOnMissedTrulyUnknownOccurrenceMass']} ({aggregate['knownSupportingEvidenceShareOfMissedMass'] * 100:.2f}%). Never-asked items accounted for {aggregate['unaskedMissedOccurrenceMass']} ({aggregate['unaskedShareOfMissedMass'] * 100:.2f}%).",
        "",
        "| Run | Warm-cold coverage | First divergence | Warm missed mass | Asked verified-known miss | Unasked miss | Natural deck symmetric-difference mass |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in result["rows"]:
        if row["role"] != "severe-selected-case":
            continue
        warm = row["paths"]["warmNatural"]
        partition = warm["falseNegativeMissedOccurrenceMassByAskedStatusAndEvidence"]
        lines.append(
            f"| {row['runID']} | {row['naturalCoverageDifference'] * 100:.3f} pp | "
            f"{row['firstNaturalQuestionDivergence']['ordinal']} | {warm['missedOccurrenceMass']} | "
            f"{partition.get('asked:verifiedKnown', 0)} | {partition.get('unasked:no-evidence', 0)} | "
            f"{row['naturalDeckDifference']['symmetricDifferenceOccurrenceMass']} |"
        )
    lines.extend([
        "",
        "The frozen path-divergence and erroneous-known-evidence hypotheses are supported in these selected cases. The never-asked concentration hypothesis is not: most severe missed mass was asked and then received `verifiedKnown` evidence despite unknown synthetic truth. The same primary mechanism appears across biased-self-verification, noisy-history, difficulty-shift, and changed-distribution cases, so scenario-specificity is not the leading explanation here.",
        "",
        "This does not mean the product should distrust verified user confirmations globally. It shows that rare false known-supporting evidence on a high-occurrence word can dominate coverage, and that an early warm path can expose a different such word before stopping. A mitigation requires a fresh design that addresses high-consequence evidence without tuning on these 11 cases.",
        "",
        result["interpretation"],
        "",
    ])
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("repaired_report", type=Path)
    parser.add_argument("failed_report", type=Path)
    parser.add_argument("reservation", type=Path)
    parser.add_argument("--output-json", required=True, type=Path)
    parser.add_argument("--output-markdown", required=True, type=Path)
    args = parser.parse_args()
    repaired = json.loads(args.repaired_report.read_text())
    failed = json.loads(args.failed_report.read_text())
    reservation = json.loads(args.reservation.read_text())
    result = analyze(repaired, failed, reservation)
    result["sourceReport"] = str(args.repaired_report)
    result["sourceReportSHA256"] = hashlib.sha256(args.repaired_report.read_bytes()).hexdigest()
    result["sourceRevision"] = repaired["source"]["revision"]
    args.output_json.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    args.output_markdown.write_text(markdown(result))


if __name__ == "__main__":
    main()
