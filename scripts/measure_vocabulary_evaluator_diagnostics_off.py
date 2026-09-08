#!/usr/bin/env python3
"""Compare diagnostics-off evaluator startup/runtime against a baseline binary."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import subprocess
import tempfile
import time
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def run_once(executable: Path, label: str, index: int, directory: Path) -> tuple[float, str, str]:
    json_path = directory / f"{label}-{index}.json"
    markdown_path = directory / f"{label}-{index}.md"
    command = [
        str(executable),
        "--seed", "42",
        "--readers", "2",
        "--documents", "2",
        "--lemmas", "60",
        "--no-gate",
        "--json", str(json_path),
        "--markdown", str(markdown_path),
    ]
    started = time.perf_counter_ns()
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    elapsed = (time.perf_counter_ns() - started) / 1_000_000
    return elapsed, sha256(json_path), sha256(markdown_path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--repetitions", type=int, default=7)
    args = parser.parse_args()
    if args.repetitions < 2:
        parser.error("at least two repetitions are required")
    for executable in (args.baseline, args.candidate):
        if not executable.is_file() or not os.access(executable, os.X_OK):
            parser.error(f"not an executable: {executable}")

    with tempfile.TemporaryDirectory(prefix="leafreader-diagnostics-off-") as temporary:
        directory = Path(temporary)
        run_once(args.baseline, "baseline-warmup", 0, directory)
        run_once(args.candidate, "candidate-warmup", 0, directory)
        baseline: list[float] = []
        candidate: list[float] = []
        baseline_hashes: set[tuple[str, str]] = set()
        candidate_hashes: set[tuple[str, str]] = set()
        for index in range(args.repetitions):
            order = (
                ((args.baseline, "baseline", baseline, baseline_hashes),
                 (args.candidate, "candidate", candidate, candidate_hashes))
                if index % 2 == 0 else
                ((args.candidate, "candidate", candidate, candidate_hashes),
                 (args.baseline, "baseline", baseline, baseline_hashes))
            )
            for executable, label, timings, hashes in order:
                elapsed, json_hash, markdown_hash = run_once(executable, label, index, directory)
                timings.append(elapsed)
                hashes.add((json_hash, markdown_hash))
        if len(baseline_hashes) != 1 or len(candidate_hashes) != 1:
            raise RuntimeError("diagnostics-off output was nondeterministic")
        baseline_json, baseline_markdown = next(iter(baseline_hashes))
        candidate_json, candidate_markdown = next(iter(candidate_hashes))
    if (baseline_json, baseline_markdown) != (candidate_json, candidate_markdown):
        raise RuntimeError("candidate diagnostics-off output differs from baseline")

    baseline_mean = sum(baseline) / len(baseline)
    candidate_mean = sum(candidate) / len(candidate)
    report = {
        "schemaVersion": 1,
        "workload": {"seed": 42, "readers": 2, "documents": 2, "lemmas": 60},
        "repetitions": args.repetitions,
        "executionOrder": "paired alternating order after one warmup per executable",
        "units": "milliseconds",
        "baselineExecutableSHA256": sha256(args.baseline),
        "candidateExecutableSHA256": sha256(args.candidate),
        "baselineRawMilliseconds": baseline,
        "candidateRawMilliseconds": candidate,
        "baselineMeanMilliseconds": baseline_mean,
        "candidateMeanMilliseconds": candidate_mean,
        "meanDeltaMilliseconds": candidate_mean - baseline_mean,
        "meanDeltaFraction": (candidate_mean / baseline_mean - 1) if baseline_mean else None,
        "outputParity": {
            "jsonSHA256": baseline_json,
            "markdownSHA256": baseline_markdown,
            "byteIdentical": True,
        },
        "environment": {
            "machine": platform.machine(),
            "platform": platform.platform(),
            "python": platform.python_version(),
        },
        "limitation": "Whole-process wall-clock measurements on the current host include scheduler and load noise. This diagnostics-off comparison is separate from the product 150 ms answer-to-next-card gate.",
    }
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
