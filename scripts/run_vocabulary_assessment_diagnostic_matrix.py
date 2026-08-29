#!/usr/bin/env python3
"""Run paired, development-only vocabulary model sensitivity experiments.

This matrix diagnoses which model boundary a synthetic failure is sensitive to.
It does not tune production defaults, select a candidate, or run the frozen
release holdout.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import tempfile
from dataclasses import asdict, dataclass, replace
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
EVALUATOR = ROOT / "scripts" / "evaluate_vocabulary_assessment.sh"
MATRIX_VERSION = "vocabulary-diagnostic-matrix-v1"


@dataclass(frozen=True)
class ModelConfiguration:
    evidence_reliability_scale: float = 1.0
    epsilon_knowledge_minimum: float = 0.05
    difficulty_prior_sd_scale: float = 1.0
    coverage_quantile: float = 0.05
    warm_prior_weight: float = 0.90

    def arguments(self) -> list[str]:
        return [
            "--evidence-reliability-scale", str(self.evidence_reliability_scale),
            "--epsilon-knowledge-minimum", str(self.epsilon_knowledge_minimum),
            "--difficulty-prior-sd-scale", str(self.difficulty_prior_sd_scale),
            "--coverage-quantile", str(self.coverage_quantile),
            "--warm-prior-weight", str(self.warm_prior_weight),
        ]


@dataclass(frozen=True)
class Factor:
    name: str
    subsystem: str
    field: str
    low: float
    high: float
    metrics: tuple[tuple[str, float], ...]


BASELINE = ModelConfiguration()
FACTORS = (
    Factor(
        "evidence-reliability",
        "observationModel",
        "evidence_reliability_scale",
        0.80,
        1.05,
        (
            ("responseNoiseCoverageHitRate", 0.02),
            ("responseNoiseCoverageBrier", 0.01),
            ("responseNoiseCoverageECE", 0.01),
        ),
    ),
    Factor(
        "epsilon-knowledge",
        "latentKnowledgeModel",
        "epsilon_knowledge_minimum",
        0.025,
        0.10,
        (
            ("thetaInterval90Coverage", 0.05),
            ("wellSpecifiedCoverageECE", 0.01),
            ("itemResidualCoverageHitRate", 0.02),
        ),
    ),
    Factor(
        "difficulty-prior-sd",
        "latentKnowledgeModel",
        "difficulty_prior_sd_scale",
        0.50,
        1.50,
        (
            ("itemResidualCoverageHitRate", 0.02),
            ("itemResidualCoverageBrier", 0.01),
            ("thetaInterval90Coverage", 0.05),
        ),
    ),
    Factor(
        "coverage-quantile",
        "coverageDeckDecision",
        "coverage_quantile",
        0.025,
        0.10,
        (
            ("minimumDeckPrecision", 0.02),
            ("responseNoiseCoverageHitRate", 0.02),
            ("idiosyncraticCoverageHitRate", 0.02),
            ("coverageMeanQuestionCount", 2.0),
        ),
    ),
    Factor(
        "warm-prior-weight",
        "warmPrior",
        "warm_prior_weight",
        0.75,
        0.98,
        (
            ("warmStartQuestionReduction", 0.02),
            ("warmStartCoverageHitDelta", 0.02),
        ),
    ),
)


def derived_seed(ordinal: int) -> int:
    digest = hashlib.sha256(f"{MATRIX_VERSION}:development:{ordinal}".encode()).digest()
    return int.from_bytes(digest[:8], "big") or 1


def source_revision() -> str:
    revision = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, check=True, capture_output=True, text=True,
    ).stdout.strip()
    dirty = subprocess.run(
        ["git", "diff", "--quiet", "HEAD", "--", "Sources", "Tests", "scripts"],
        cwd=ROOT,
        check=False,
    ).returncode
    return revision + ("+dirty" if dirty else "")


def variants() -> list[tuple[str, str, str, ModelConfiguration]]:
    result = [("baseline", "baseline", "baseline", BASELINE)]
    for factor in FACTORS:
        result.extend((
            (
                f"{factor.name}-low",
                factor.name,
                "low",
                replace(BASELINE, **{factor.field: factor.low}),
            ),
            (
                f"{factor.name}-high",
                factor.name,
                "high",
                replace(BASELINE, **{factor.field: factor.high}),
            ),
        ))
    return result


def indexed_results(report: dict) -> dict[tuple[str, str], dict]:
    return {(item["scenario"], item["mode"]): item for item in report["results"]}


def metrics(report: dict) -> dict[str, float]:
    indexed = indexed_results(report)
    gates = report["qualityGates"]
    diagnostics = report["protocolDiagnostics"]
    coverage_rows = [item for item in report["results"] if item["mode"] == "coverage-98"]
    return {
        "thetaInterval90Coverage": gates["thetaInterval90Coverage"],
        "wellSpecifiedCoverageHitRate": gates["coverage98HitRate"],
        "itemResidualCoverageHitRate": gates["itemResidualCoverageHitRate"],
        "responseNoiseCoverageHitRate": gates["responseNoiseCoverageHitRate"],
        "idiosyncraticCoverageHitRate": gates["idiosyncraticCoverageHitRate"],
        "minimumDeckPrecision": gates["minimumDeckPrecision"],
        "warmStartQuestionReduction": gates["warmStartQuestionReduction"],
        "warmStartCoverageHitDelta": gates["warmStartCoverageHitDelta"],
        "wellSpecifiedCoverageECE": indexed[("well-specified-rasch", "coverage-98")]["expectedCalibrationError"],
        "itemResidualCoverageBrier": indexed[("item-residual", "coverage-98")]["brierScore"],
        "responseNoiseCoverageBrier": indexed[("response-noise", "coverage-98")]["brierScore"],
        "responseNoiseCoverageECE": indexed[("response-noise", "coverage-98")]["expectedCalibrationError"],
        "coverageMeanQuestionCount": sum(item["meanQuestionCount"] for item in coverage_rows)
        / len(coverage_rows),
        "coldCoverageHitRate": diagnostics["coldCoverageHitRate"],
        "warmCoverageHitRate": diagnostics["warmCoverageHitRate"],
    }


def gate_failures(report: dict) -> list[str]:
    values = metrics(report)
    failures = []
    if report["qualityGates"]["wellSpecifiedECE"] > 0.05:
        failures.append("wellSpecifiedECE")
    if not 0.85 <= values["thetaInterval90Coverage"] <= 0.95:
        failures.append("thetaInterval90Coverage")
    for field, minimum in (
        ("wellSpecifiedCoverageHitRate", 0.95),
        ("itemResidualCoverageHitRate", 0.95),
        ("responseNoiseCoverageHitRate", 0.90),
        ("idiosyncraticCoverageHitRate", 0.85),
        ("minimumDeckPrecision", 0.50),
        ("warmStartQuestionReduction", 0.25),
    ):
        if values[field] < minimum:
            failures.append(field)
    if values["warmStartCoverageHitDelta"] < -0.02:
        failures.append("warmStartCoverageHitDelta")
    return failures


def attribution(experiments: list[dict]) -> list[dict]:
    baselines = {
        experiment["seed"]: experiment for experiment in experiments
        if experiment["factor"] == "baseline"
    }
    summaries = []
    for factor in FACTORS:
        comparisons = []
        material_metrics = set()
        signs: dict[tuple[str, str], set[int]] = {}
        for experiment in experiments:
            if experiment["factor"] != factor.name:
                continue
            baseline = baselines[experiment["seed"]]
            deltas = {}
            for metric, threshold in factor.metrics:
                delta = experiment["metrics"][metric] - baseline["metrics"][metric]
                material = abs(delta) >= threshold
                deltas[metric] = {
                    "delta": delta,
                    "materialityThreshold": threshold,
                    "material": material,
                }
                if material:
                    material_metrics.add(metric)
                    signs.setdefault((experiment["level"], metric), set()).add(1 if delta > 0 else -1)
            comparisons.append({
                "experimentID": experiment["experimentID"],
                "seed": experiment["seed"],
                "level": experiment["level"],
                "deltas": deltas,
            })
        mixed = any(len(values) > 1 for values in signs.values())
        status = (
            "not-supported" if not material_metrics
            else "inconclusive" if mixed
            else "supported"
        )
        summaries.append({
            "factor": factor.name,
            "subsystem": factor.subsystem,
            "originEvidence": status,
            "materialMetrics": sorted(material_metrics),
            "comparisons": comparisons,
        })
    return summaries


def truth_fingerprints(report: dict) -> dict[str, str]:
    fingerprints = {
        f"{item['scenario']}:{item['mode']}": item.get("syntheticTruthFingerprint")
        for item in report["results"]
    }
    fingerprints["warm-start"] = report["protocolDiagnostics"].get("syntheticTruthFingerprint")
    if any(not value for value in fingerprints.values()):
        raise RuntimeError("paired diagnostic report lacks synthetic truth fingerprints")
    return fingerprints


def verify_truth_pairing(experiments: list[dict]) -> None:
    baselines = {
        experiment["seed"]: truth_fingerprints(experiment["report"])
        for experiment in experiments if experiment["factor"] == "baseline"
    }
    for experiment in experiments:
        if truth_fingerprints(experiment["report"]) != baselines[experiment["seed"]]:
            raise RuntimeError(
                f"synthetic truth changed for {experiment['experimentID']} despite paired seed"
            )


def markdown(report: dict) -> str:
    lines = [
        "# Vocabulary assessment diagnostic matrix",
        "",
        f"Matrix: `{report['matrixVersion']}`; source: `{report['sourceRevision']}`.",
        "",
        "This is paired synthetic sensitivity evidence on development seeds only. "
        "It does not validate human calibration, select production parameters, or run the frozen release holdout.",
        "",
        "| Factor | Tested subsystem | Origin evidence | Material metrics |",
        "|---|---|---|---|",
    ]
    for item in report["attribution"]:
        material = ", ".join(item["materialMetrics"]) or "none"
        lines.append(
            f"| {item['factor']} | {item['subsystem']} | {item['originEvidence']} | {material} |"
        )
    lines.extend((
        "",
        "`supported` means the predeclared one-factor perturbation materially moved at least one mapped metric "
        "with a consistent direction for the same level across seeds. It does not prove that subsystem is the sole cause.",
        "",
        "## Baseline failures retained",
        "",
        "| Seed | Failures |",
        "|---:|---|",
    ))
    for experiment in report["experiments"]:
        if experiment["factor"] == "baseline":
            failures = ", ".join(experiment["gateFailures"]) or "none"
            lines.append(f"| {experiment['seed']} | {failures} |")
    lines.append("")
    return "\n".join(lines)


def self_test() -> None:
    baseline_metrics = {metric: 0.5 for factor in FACTORS for metric, _ in factor.metrics}
    experiments = [
        {
            "experimentID": "baseline-1",
            "factor": "baseline",
            "level": "baseline",
            "seed": 1,
            "metrics": baseline_metrics,
        }
    ]
    for factor in FACTORS:
        changed = dict(baseline_metrics)
        metric, threshold = factor.metrics[0]
        changed[metric] += threshold
        experiments.append({
            "experimentID": f"{factor.name}-high-1",
            "factor": factor.name,
            "level": "high",
            "seed": 1,
            "metrics": changed,
        })
    summaries = attribution(experiments)
    assert all(item["originEvidence"] == "supported" for item in summaries)
    paired_report = {
        "results": [{
            "scenario": "fixture",
            "mode": "coverage-98",
            "syntheticTruthFingerprint": "truth-a",
        }],
        "protocolDiagnostics": {"syntheticTruthFingerprint": "truth-warm"},
    }
    verify_truth_pairing([
        {"experimentID": "base", "factor": "baseline", "seed": 1, "report": paired_report},
        {"experimentID": "variant", "factor": "fixture", "seed": 1, "report": paired_report},
    ])
    assert len(variants()) == 11
    assert derived_seed(0) == derived_seed(0)
    assert derived_seed(0) != derived_seed(1)
    print("vocabulary diagnostic matrix self-test passed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-json", type=Path, default=Path("vocabulary-diagnostic-matrix.json"))
    parser.add_argument("--output-markdown", type=Path, default=Path("vocabulary-diagnostic-matrix.md"))
    parser.add_argument("--readers", type=int, default=8)
    parser.add_argument("--lemmas", type=int, default=120)
    parser.add_argument("--documents", type=int, default=4)
    parser.add_argument("--runs", type=int, default=2)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if args.readers < 1 or args.lemmas < 20 or args.documents < 1 or args.runs < 1:
        parser.error("readers/documents/runs must be positive and lemmas must be at least 20")

    plan = [
        (identifier, factor, level, configuration, ordinal, derived_seed(ordinal))
        for ordinal in range(args.runs)
        for identifier, factor, level, configuration in variants()
    ]
    if args.dry_run:
        for identifier, factor, level, configuration, ordinal, seed in plan:
            print(
                f"{identifier} factor={factor} level={level} run={ordinal + 1} "
                f"seed={seed} configuration={asdict(configuration)}"
            )
        return 0

    factor_by_name = {factor.name: factor for factor in FACTORS}
    experiments = []
    with tempfile.TemporaryDirectory(prefix="leafreader-vocabulary-diagnostic-") as temporary:
        temporary_root = Path(temporary)
        for identifier, factor, level, configuration, ordinal, seed in plan:
            json_path = temporary_root / f"{identifier}-{ordinal}.json"
            markdown_path = temporary_root / f"{identifier}-{ordinal}.md"
            command = [
                str(EVALUATOR),
                "--seed", str(seed),
                "--readers", str(args.readers),
                "--documents", str(min(args.documents, args.readers)),
                "--lemmas", str(args.lemmas),
                "--item-residual-sd", "0.8",
                "--response-noise-rate", "0.12",
                "--idiosyncratic-flip-rate", "0.12",
                "--no-gate",
                "--paired-diagnostic-substreams",
                "--json", str(json_path),
                "--markdown", str(markdown_path),
                *configuration.arguments(),
            ]
            completed = subprocess.run(command, cwd=ROOT, check=False, stdout=subprocess.DEVNULL)
            if completed.returncode != 0 or not json_path.exists():
                raise RuntimeError(
                    f"development evaluator failed for {identifier} seed {seed}: {completed.returncode}"
                )
            evaluator_report = json.loads(json_path.read_text(encoding="utf-8"))
            experiments.append({
                "experimentID": f"{identifier}-run-{ordinal + 1}",
                "factor": factor,
                "level": level,
                "testedSubsystem": factor_by_name[factor].subsystem if factor != "baseline" else "baseline",
                "seed": seed,
                "modelConfiguration": asdict(configuration),
                "evaluatorExitCode": completed.returncode,
                "gateFailures": gate_failures(evaluator_report),
                "metrics": metrics(evaluator_report),
                "report": evaluator_report,
            })

    verify_truth_pairing(experiments)
    report = {
        "schemaVersion": 1,
        "matrixVersion": MATRIX_VERSION,
        "sourceRevision": source_revision(),
        "syntheticOnly": True,
        "releaseHoldoutTouched": False,
        "selectionOrTuningPerformed": False,
        "truthPairingVerified": True,
        "configuration": {
            "readersPerScenario": args.readers,
            "documentsPerScenario": min(args.documents, args.readers),
            "lemmaCount": args.lemmas,
            "runsPerConfiguration": args.runs,
            "populationParameters": {
                "itemResidualStandardDeviation": 0.8,
                "responseNoiseRate": 0.12,
                "idiosyncraticFlipRate": 0.12,
            },
            "baselineModelConfiguration": asdict(BASELINE),
        },
        "factorDefinitions": [asdict(factor) for factor in FACTORS],
        "experiments": experiments,
        "attribution": attribution(experiments),
    }
    args.output_json.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    args.output_markdown.write_text(markdown(report), encoding="utf-8")
    print(markdown(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
