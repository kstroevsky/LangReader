#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path


EXPECTED_RESULTS = {
    (scenario, mode)
    for scenario in (
        "well-specified-rasch",
        "item-residual",
        "response-noise",
        "idiosyncratic-knowledge",
    )
    for mode in ("all-unknown", "coverage-98")
}


def fail(message: str) -> None:
    raise ValueError(message)


def load(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read {path}: {error}")


def summarize(report: dict) -> dict:
    if report.get("schemaVersion") != 1:
        fail("unsupported schemaVersion")
    configuration = report.get("configuration")
    if not isinstance(configuration, dict):
        fail("configuration must be an object")
    for field in ("seed", "readersPerScenario", "lemmaCount", "algorithmVersion"):
        if not isinstance(configuration.get(field), int):
            fail(f"configuration lacks integer {field}")
    if configuration["algorithmVersion"] >= 3:
        if not isinstance(configuration.get("documentsPerScenario"), int):
            fail("algorithm version 3+ report lacks integer documentsPerScenario")
        parameters = configuration.get("populationParameters")
        if not isinstance(parameters, dict):
            fail("algorithm version 3+ report lacks populationParameters")
        for field in ("itemResidualStandardDeviation", "responseNoiseRate", "idiosyncraticFlipRate"):
            if not isinstance(parameters.get(field), (int, float)):
                fail(f"populationParameters lacks numeric {field}")
        model_parameters = configuration.get("assessmentModelParameters")
        if model_parameters is not None:
            if not isinstance(model_parameters, dict):
                fail("assessmentModelParameters must be an object")
            for field in (
                "evidenceReliabilityScale",
                "minimumEpsilonKnowledge",
                "difficultyPriorStandardDeviationScale",
                "coverageQuantile",
                "warmPriorWeight",
            ):
                if not isinstance(model_parameters.get(field), (int, float)):
                    fail(f"assessmentModelParameters lacks numeric {field}")
            if model_parameters.get("coverageStoppingComputation", "staged") not in (
                "staged", "full-every-answer"
            ):
                fail("assessmentModelParameters has invalid coverageStoppingComputation")
        paired = configuration.get("usesPairedDiagnosticSubstreams", False)
        if not isinstance(paired, bool):
            fail("usesPairedDiagnosticSubstreams must be boolean")
    results = report.get("results")
    if not isinstance(results, list):
        fail("results must be an array")
    indexed = {(item.get("scenario"), item.get("mode")): item for item in results}
    if set(indexed) != EXPECTED_RESULTS:
        fail("report must contain all four scenarios and both modes exactly once")
    numeric_fields = (
        "brierScore",
        "logLoss",
        "expectedCalibrationError",
        "thetaRMSE",
        "thetaInterval90Coverage",
        "deckPrecision",
        "deckRecall",
        "realizedTokenCoverage",
        "targetMissRate",
        "oracleDeckRegret",
        "meanQuestionCount",
    )
    for item in results:
        for field in numeric_fields:
            if not isinstance(item.get(field), (int, float)):
                fail(f"{item.get('scenario')}/{item.get('mode')} lacks numeric {field}")
        if not isinstance(item.get("stopReasons"), dict):
            fail("stopReasons must be an object")
        if configuration.get("usesPairedDiagnosticSubstreams"):
            if not isinstance(item.get("syntheticTruthFingerprint"), str):
                fail("paired diagnostic result lacks syntheticTruthFingerprint")

    well = [indexed[("well-specified-rasch", mode)] for mode in ("all-unknown", "coverage-98")]
    brier = sum(item["brierScore"] for item in well) / 2
    ece = sum(item["expectedCalibrationError"] for item in well) / 2
    interval = sum(item["thetaInterval90Coverage"] for item in well) / 2
    hit_rate = 1 - indexed[("well-specified-rasch", "coverage-98")]["targetMissRate"]
    gates = report.get("qualityGates")
    if not isinstance(gates, dict):
        fail("qualityGates must be an object")
    if configuration.get("usesPairedDiagnosticSubstreams"):
        diagnostics = report.get("protocolDiagnostics")
        if not isinstance(diagnostics, dict) or not isinstance(
            diagnostics.get("syntheticTruthFingerprint"), str
        ):
            fail("paired protocol diagnostics lack syntheticTruthFingerprint")
    if gates.get("eligible"):
        if ece > 0.05:
            fail(f"well-specified ECE {ece:.6f} exceeds 0.05")
        if not 0.85 <= interval <= 0.95:
            fail(f"90% theta interval coverage {interval:.6f} is outside 0.85...0.95")
        if hit_rate < 0.95:
            fail(f"coverage hit rate {hit_rate:.6f} is below 0.95")
        required_hits = {
            "item-residual": 0.95,
            "response-noise": 0.90,
            "idiosyncratic-knowledge": 0.85,
        }
        for scenario, minimum in required_hits.items():
            scenario_hit = 1 - indexed[(scenario, "coverage-98")]["targetMissRate"]
            if scenario_hit < minimum:
                fail(f"{scenario} coverage hit rate {scenario_hit:.6f} is below {minimum:.2f}")
        minimum_precision = min(item["deckPrecision"] for item in results)
        if minimum_precision < 0.50:
            fail(f"minimum deck precision {minimum_precision:.6f} is below 0.50")
        diagnostics = report.get("protocolDiagnostics")
        if not isinstance(diagnostics, dict):
            fail("protocolDiagnostics must be an object")
        if diagnostics.get("warmStartQuestionReduction", 0) < 0.25:
            fail("warm start does not reduce question count by at least 25%")
        if diagnostics.get("coldCoverageHitRate", 0) - diagnostics.get("warmCoverageHitRate", 0) > 0.02:
            fail("warm start coverage hit degraded by more than two percentage points")
        if gates.get("passed") is not True:
            fail("eligible report says quality gates did not pass")
    return {
        "configuration": configuration,
        "brier": {(item["scenario"], item["mode"]): item["brierScore"] for item in results},
        "ece": {(item["scenario"], item["mode"]): item["expectedCalibrationError"] for item in results},
        "coverage": {scenario: 1 - indexed[(scenario, "coverage-98")]["targetMissRate"] for scenario, _ in EXPECTED_RESULTS},
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    parser.add_argument("--baseline", type=Path)
    arguments = parser.parse_args()
    try:
        current = summarize(load(arguments.report))
        if arguments.baseline:
            baseline = summarize(load(arguments.baseline))
            if current["configuration"] != baseline["configuration"]:
                fail("current report and baseline use different seed, workload, algorithm, or population parameters")
            for key, value in current["brier"].items():
                if value - baseline["brier"][key] > 0.01:
                    fail(f"{key} Brier score degraded by more than 0.01")
            for key, value in current["ece"].items():
                if value - baseline["ece"][key] > 0.01:
                    fail(f"{key} ECE degraded by more than 0.01")
            for scenario, value in current["coverage"].items():
                if baseline["coverage"][scenario] - value > 0.02:
                    fail(f"{scenario} coverage hit rate degraded by more than two percentage points")
    except ValueError as error:
        print(f"vocabulary assessment report invalid: {error}", file=sys.stderr)
        return 1
    print("vocabulary assessment report valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
