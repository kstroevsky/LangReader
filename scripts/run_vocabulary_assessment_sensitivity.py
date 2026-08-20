#!/usr/bin/env python3
"""Run predeclared multi-seed synthetic vocabulary robustness suites.

This runner is an anti-cherry-picking guard, not a substitute for validation on
real learners. Seeds are derived from a versioned label rather than selected
after observing results. Development sweeps vary fictional population
parameters; release holdouts keep the reviewed nominal population and require
every constituent evaluator run to pass its engineering gates.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import tempfile
from dataclasses import dataclass, asdict
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
EVALUATOR = ROOT / "scripts" / "evaluate_vocabulary_assessment.sh"
SUITE_VERSION = "vocabulary-synthetic-holdout-v1"


@dataclass(frozen=True)
class PopulationProfile:
    name: str
    item_residual_sd: float
    response_noise_rate: float
    idiosyncratic_flip_rate: float


PROFILES = (
    PopulationProfile("mild-mismatch", 0.50, 0.08, 0.08),
    PopulationProfile("reviewed-nominal", 0.80, 0.12, 0.12),
    PopulationProfile("severe-mismatch", 1.10, 0.16, 0.16),
)


def derived_seed(suite: str, profile: str, ordinal: int) -> int:
    digest = hashlib.sha256(f"{SUITE_VERSION}:{suite}:{profile}:{ordinal}".encode()).digest()
    return int.from_bytes(digest[:8], "big") or 1


def run_configuration(suite: str) -> tuple[tuple[PopulationProfile, ...], int, int, int, int, bool]:
    if suite == "development-sweep":
        return PROFILES, 2, 8, 120, 4, False
    if suite == "release-holdout":
        nominal = tuple(profile for profile in PROFILES if profile.name == "reviewed-nominal")
        return nominal, 3, 64, 400, 8, True
    raise ValueError(f"unknown suite: {suite}")


def summarize(runs: list[dict]) -> dict:
    cells: dict[tuple[str, str], list[dict]] = {}
    for run in runs:
        for result in run["report"]["results"]:
            cells.setdefault((result["scenario"], result["mode"]), []).append(result)
    summaries = []
    for (scenario, mode), values in sorted(cells.items()):
        summaries.append(
            {
                "scenario": scenario,
                "mode": mode,
                "runCount": len(values),
                "brierRange": [min(item["brierScore"] for item in values), max(item["brierScore"] for item in values)],
                "eceRange": [
                    min(item["expectedCalibrationError"] for item in values),
                    max(item["expectedCalibrationError"] for item in values),
                ],
                "coverageHitRange": [
                    min(1 - item["targetMissRate"] for item in values),
                    max(1 - item["targetMissRate"] for item in values),
                ],
                "questionCountRange": [
                    min(item["meanQuestionCount"] for item in values),
                    max(item["meanQuestionCount"] for item in values),
                ],
            }
        )
    eligible = [run for run in runs if run["report"]["qualityGates"]["eligible"]]
    return {
        "eligibleEngineeringGateRunCount": len(eligible),
        "allEligibleEngineeringGatesPassed": bool(eligible)
        and all(run["report"]["qualityGates"]["passed"] for run in eligible),
        "cells": summaries,
    }


def markdown(report: dict) -> str:
    lines = [
        "# Vocabulary synthetic sensitivity report",
        "",
        f"Suite: `{report['suite']}`; version: `{report['suiteVersion']}`; runs: {len(report['runs'])}.",
        "",
        "This is synthetic robustness evidence only. It does not validate probabilities or coverage on real learners.",
        "",
        "| Scenario | Mode | Brier range | ECE range | Coverage-hit range | Questions range |",
        "|---|---|---:|---:|---:|---:|",
    ]
    for cell in report["summary"]["cells"]:
        lines.append(
            "| {scenario} | {mode} | {brier[0]:.4f}–{brier[1]:.4f} | "
            "{ece[0]:.4f}–{ece[1]:.4f} | {coverage[0]:.1%}–{coverage[1]:.1%} | "
            "{questions[0]:.1f}–{questions[1]:.1f} |".format(
                scenario=cell["scenario"],
                mode=cell["mode"],
                brier=cell["brierRange"],
                ece=cell["eceRange"],
                coverage=cell["coverageHitRange"],
                questions=cell["questionCountRange"],
            )
        )
    lines.extend(
        [
            "",
            "Eligible constituent engineering gates: "
            + (
                "all passed"
                if report["summary"]["allEligibleEngineeringGatesPassed"]
                else "not evaluated" if report["summary"]["eligibleEngineeringGateRunCount"] == 0
                else "failed"
            ),
            "",
        ]
    )
    return "\n".join(lines)


def self_test() -> None:
    first = derived_seed("development-sweep", "reviewed-nominal", 0)
    assert first == derived_seed("development-sweep", "reviewed-nominal", 0)
    assert first != derived_seed("development-sweep", "reviewed-nominal", 1)
    fixture = {
        "qualityGates": {"eligible": True, "passed": True},
        "results": [
            {
                "scenario": "fixture",
                "mode": "coverage-98",
                "brierScore": 0.1,
                "expectedCalibrationError": 0.02,
                "targetMissRate": 0.05,
                "meanQuestionCount": 20,
            }
        ],
    }
    summary = summarize([{"report": fixture}, {"report": fixture}])
    assert summary["allEligibleEngineeringGatesPassed"] is True
    assert summary["cells"][0]["coverageHitRange"] == [0.95, 0.95]
    print("vocabulary sensitivity runner self-test passed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite", choices=("development-sweep", "release-holdout"), default="development-sweep")
    parser.add_argument("--output-json", type=Path, default=Path("vocabulary-sensitivity.json"))
    parser.add_argument("--output-markdown", type=Path, default=Path("vocabulary-sensitivity.md"))
    parser.add_argument("--readers", type=int)
    parser.add_argument("--lemmas", type=int)
    parser.add_argument("--documents", type=int)
    parser.add_argument("--runs-per-profile", type=int)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0

    profiles, default_runs, default_readers, default_lemmas, default_documents, enforce_gates = run_configuration(args.suite)
    runs_per_profile = args.runs_per_profile or default_runs
    readers = args.readers or default_readers
    lemmas = args.lemmas or default_lemmas
    documents = min(args.documents or default_documents, readers)
    if runs_per_profile < 1 or readers < 1 or lemmas < 20 or documents < 1:
        parser.error("runs/readers/documents must be positive and lemmas must be at least 20")

    plan = [
        (profile, ordinal, derived_seed(args.suite, profile.name, ordinal))
        for profile in profiles
        for ordinal in range(runs_per_profile)
    ]
    if args.dry_run:
        for profile, ordinal, seed in plan:
            print(
                f"{profile.name} run={ordinal + 1} seed={seed} readers={readers} "
                f"documents={documents} lemmas={lemmas}"
            )
        return 0

    runs: list[dict] = []
    with tempfile.TemporaryDirectory(prefix="leafreader-vocabulary-sensitivity-") as temporary:
        root = Path(temporary)
        for profile, ordinal, seed in plan:
            json_path = root / f"{profile.name}-{ordinal}.json"
            markdown_path = root / f"{profile.name}-{ordinal}.md"
            command = [
                str(EVALUATOR),
                "--seed", str(seed),
                "--readers", str(readers),
                "--lemmas", str(lemmas),
                "--documents", str(documents),
                "--item-residual-sd", str(profile.item_residual_sd),
                "--response-noise-rate", str(profile.response_noise_rate),
                "--idiosyncratic-flip-rate", str(profile.idiosyncratic_flip_rate),
                "--json", str(json_path),
                "--markdown", str(markdown_path),
            ]
            if not enforce_gates:
                command.append("--no-gate")
            completed = subprocess.run(command, cwd=ROOT, check=False)
            if not json_path.exists():
                raise RuntimeError(
                    f"evaluator exited {completed.returncode} without writing {json_path}"
                )
            runs.append(
                {
                    "profile": asdict(profile),
                    "ordinal": ordinal + 1,
                    "seed": seed,
                    "evaluatorExitCode": completed.returncode,
                    "report": json.loads(json_path.read_text(encoding="utf-8")),
                }
            )

    report = {
        "schemaVersion": 1,
        "suite": args.suite,
        "suiteVersion": SUITE_VERSION,
        "syntheticOnly": True,
        "configuration": {
            "readersPerScenario": readers,
            "documentsPerScenario": documents,
            "lemmaCount": lemmas,
        },
        "runs": runs,
        "summary": summarize(runs),
    }
    args.output_json.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    args.output_markdown.write_text(markdown(report), encoding="utf-8")
    print(markdown(report))
    if enforce_gates and not report["summary"]["allEligibleEngineeringGatesPassed"]:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
