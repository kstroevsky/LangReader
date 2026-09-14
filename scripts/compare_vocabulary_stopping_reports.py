#!/usr/bin/env python3
"""Compare paired staged/full vocabulary stopping reports on development seeds."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def base_configuration(report: dict) -> dict:
    configuration = json.loads(json.dumps(report["configuration"]))
    configuration["assessmentModelParameters"].pop("coverageStoppingComputation", None)
    return configuration


def indexed_results(report: dict) -> dict[tuple[str, str], dict]:
    return {(item["scenario"], item["mode"]): item for item in report["results"]}


def compare(full_reports: list[dict], staged_reports: list[dict]) -> dict:
    if not full_reports or len(full_reports) != len(staged_reports):
        raise ValueError("full and staged report counts must match and be nonzero")
    per_run = []
    paired = []
    for full, staged in zip(full_reports, staged_reports):
        if base_configuration(full) != base_configuration(staged):
            raise ValueError("paired reports use different workloads or model parameters")
        full_strategy = full["configuration"]["assessmentModelParameters"].get(
            "coverageStoppingComputation"
        )
        staged_strategy = staged["configuration"]["assessmentModelParameters"].get(
            "coverageStoppingComputation"
        )
        if full_strategy != "full-every-answer" or staged_strategy != "staged":
            raise ValueError("paired reports do not identify full and staged strategies")
        full_results = indexed_results(full)
        staged_results = indexed_results(staged)
        if set(full_results) != set(staged_results):
            raise ValueError("paired reports contain different result populations")
        for key in full_results:
            if full_results[key].get("syntheticTruthFingerprint") != staged_results[key].get(
                "syntheticTruthFingerprint"
            ):
                raise ValueError(f"synthetic truth mismatch for {key}")
            paired.append((key, full_results[key], staged_results[key]))
        full_protocol = full["protocolDiagnostics"]
        staged_protocol = staged["protocolDiagnostics"]
        if full_protocol.get("syntheticTruthFingerprint") != staged_protocol.get(
            "syntheticTruthFingerprint"
        ):
            raise ValueError("warm-start synthetic truth mismatch")
        per_run.append({
            "seed": full["configuration"]["seed"],
            "fullWarmCoverageHitRate": full_protocol["warmCoverageHitRate"],
            "stagedWarmCoverageHitRate": staged_protocol["warmCoverageHitRate"],
            "fullWarmMeanQuestionCount": full_protocol["warmMeanQuestionCount"],
            "stagedWarmMeanQuestionCount": staged_protocol["warmMeanQuestionCount"],
            "stagedWarmStartQuestionReduction": staged_protocol["warmStartQuestionReduction"],
        })

    aggregate = []
    for key in sorted({entry[0] for entry in paired}):
        entries = [(full, staged) for candidate, full, staged in paired if candidate == key]
        full_brier = mean([full["brierScore"] for full, _ in entries])
        staged_brier = mean([staged["brierScore"] for _, staged in entries])
        full_ece = mean([full["expectedCalibrationError"] for full, _ in entries])
        staged_ece = mean([staged["expectedCalibrationError"] for _, staged in entries])
        full_hit = mean([1 - full["targetMissRate"] for full, _ in entries])
        staged_hit = mean([1 - staged["targetMissRate"] for _, staged in entries])
        full_precision = mean([full["deckPrecision"] for full, _ in entries])
        staged_precision = mean([staged["deckPrecision"] for _, staged in entries])
        full_questions = mean([full["meanQuestionCount"] for full, _ in entries])
        staged_questions = mean([staged["meanQuestionCount"] for _, staged in entries])
        aggregate.append({
            "scenario": key[0],
            "mode": key[1],
            "brierDelta": staged_brier - full_brier,
            "eceDelta": staged_ece - full_ece,
            "coverageHitDelta": staged_hit - full_hit,
            "deckPrecisionDelta": staged_precision - full_precision,
            "questionCountDelta": staged_questions - full_questions,
            "stagedDeckPrecision": staged_precision,
        })

    coverage = [item for item in aggregate if item["mode"] == "coverage-98"]
    full_warm_hit = mean([item["fullWarmCoverageHitRate"] for item in per_run])
    staged_warm_hit = mean([item["stagedWarmCoverageHitRate"] for item in per_run])
    gates = {
        "maximumBrierDegradation": max(item["brierDelta"] for item in coverage),
        "maximumECEDegradation": max(item["eceDelta"] for item in coverage),
        "minimumCoverageHitDelta": min(item["coverageHitDelta"] for item in coverage),
        "minimumStagedDeckPrecision": min(item["stagedDeckPrecision"] for item in coverage),
        "aggregateWarmCoverageHitDelta": staged_warm_hit - full_warm_hit,
        "minimumStagedWarmQuestionReduction": min(
            item["stagedWarmStartQuestionReduction"] for item in per_run
        ),
    }
    gates["passed"] = (
        gates["maximumBrierDegradation"] <= 0.01
        and gates["maximumECEDegradation"] <= 0.01
        and gates["minimumCoverageHitDelta"] >= -0.02
        and gates["minimumStagedDeckPrecision"] >= 0.50
        and gates["aggregateWarmCoverageHitDelta"] >= -0.02
        and gates["minimumStagedWarmQuestionReduction"] >= 0.25
    )
    return {
        "schemaVersion": 1,
        "suite": "development-stopping-strategy-comparison",
        "confirmatoryOrReleaseHoldout": False,
        "runCount": len(per_run),
        "perRun": per_run,
        "aggregate": aggregate,
        "gates": gates,
    }


def markdown(report: dict) -> str:
    lines = [
        "# Vocabulary coverage-stopping development comparison",
        "",
        f"Paired runs: {report['runCount']}. This is development evidence, not the frozen release holdout or real-learner validation.",
        "",
        "| Scenario | Mode | Δ Brier | Δ ECE | Δ coverage hit | Δ precision | Δ questions |",
        "|---|---|---:|---:|---:|---:|---:|",
    ]
    for item in report["aggregate"]:
        lines.append(
            f"| {item['scenario']} | {item['mode']} | {item['brierDelta']:+.4f} | "
            f"{item['eceDelta']:+.4f} | {item['coverageHitDelta']:+.2%} | "
            f"{item['deckPrecisionDelta']:+.4f} | {item['questionCountDelta']:+.2f} |"
        )
    lines.extend(["", "Per-seed warm results:", ""])
    for item in report["perRun"]:
        lines.append(
            f"- `{item['seed']}`: coverage {item['fullWarmCoverageHitRate']:.2%} → "
            f"{item['stagedWarmCoverageHitRate']:.2%}; questions "
            f"{item['fullWarmMeanQuestionCount']:.2f} → {item['stagedWarmMeanQuestionCount']:.2f}."
        )
    lines.extend([
        "",
        "Comparison gates: " + ("PASS." if report["gates"]["passed"] else "FAIL."),
        "",
    ])
    return "\n".join(lines)


def self_test() -> None:
    def fixture(strategy: str, hit: float) -> dict:
        results = []
        for scenario in ("well-specified-rasch", "item-residual", "response-noise", "idiosyncratic-knowledge"):
            for mode in ("all-unknown", "coverage-98"):
                results.append({
                    "scenario": scenario, "mode": mode, "brierScore": 0.1,
                    "expectedCalibrationError": 0.02, "targetMissRate": 1 - hit,
                    "deckPrecision": 0.7, "meanQuestionCount": 60,
                    "syntheticTruthFingerprint": f"{scenario}-{mode}",
                })
        return {
            "configuration": {
                "seed": 1,
                "readersPerScenario": 64,
                "assessmentModelParameters": {"coverageStoppingComputation": strategy},
            },
            "results": results,
            "protocolDiagnostics": {
                "syntheticTruthFingerprint": "warm",
                "warmCoverageHitRate": hit,
                "warmMeanQuestionCount": 20,
                "warmStartQuestionReduction": 0.5,
            },
        }
    report = compare([fixture("full-every-answer", 0.98)], [fixture("staged", 0.98)])
    assert report["gates"]["passed"] is True
    adverse = compare([fixture("full-every-answer", 0.98)], [fixture("staged", 0.90)])
    assert adverse["gates"]["passed"] is False
    print("vocabulary stopping comparison self-test passed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--full", nargs="+", type=Path)
    parser.add_argument("--staged", nargs="+", type=Path)
    parser.add_argument("--output-json", type=Path)
    parser.add_argument("--output-markdown", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if not args.full or not args.staged:
        parser.error("provide paired --full and --staged reports")
    report = compare([load(path) for path in args.full], [load(path) for path in args.staged])
    report["inputSHA256"] = hashlib.sha256(
        b"".join(path.read_bytes() for path in args.full + args.staged)
    ).hexdigest()
    rendered = markdown(report)
    if args.output_json:
        args.output_json.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if args.output_markdown:
        args.output_markdown.write_text(rendered, encoding="utf-8")
    print(rendered)
    return 0 if report["gates"]["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
