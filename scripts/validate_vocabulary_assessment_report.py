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


def summarize(report: dict) -> tuple[float, float, float]:
    if report.get("schemaVersion") != 1:
        fail("unsupported schemaVersion")
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

    well = [indexed[("well-specified-rasch", mode)] for mode in ("all-unknown", "coverage-98")]
    brier = sum(item["brierScore"] for item in well) / 2
    ece = sum(item["expectedCalibrationError"] for item in well) / 2
    interval = sum(item["thetaInterval90Coverage"] for item in well) / 2
    hit_rate = 1 - indexed[("well-specified-rasch", "coverage-98")]["targetMissRate"]
    gates = report.get("qualityGates")
    if not isinstance(gates, dict):
        fail("qualityGates must be an object")
    if gates.get("eligible"):
        if ece > 0.05:
            fail(f"well-specified ECE {ece:.6f} exceeds 0.05")
        if not 0.85 <= interval <= 0.95:
            fail(f"90% theta interval coverage {interval:.6f} is outside 0.85...0.95")
        if hit_rate < 0.95:
            fail(f"coverage hit rate {hit_rate:.6f} is below 0.95")
        if gates.get("passed") is not True:
            fail("eligible report says quality gates did not pass")
    return brier, ece, hit_rate


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    parser.add_argument("--baseline", type=Path)
    arguments = parser.parse_args()
    try:
        current = summarize(load(arguments.report))
        if arguments.baseline:
            baseline = summarize(load(arguments.baseline))
            if current[0] - baseline[0] > 0.01:
                fail("well-specified Brier score degraded by more than 0.01")
            if current[1] - baseline[1] > 0.01:
                fail("well-specified ECE degraded by more than 0.01")
            if baseline[2] - current[2] > 0.02:
                fail("coverage hit rate degraded by more than two percentage points")
    except ValueError as error:
        print(f"vocabulary assessment report invalid: {error}", file=sys.stderr)
        return 1
    print("vocabulary assessment report valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
