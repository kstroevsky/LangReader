#!/usr/bin/env python3
"""Compare the current vocabulary runners with the frozen development baseline."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "docs/plans/vocabulary-validation-boundary/implementation-evidence"
MANIFEST = EVIDENCE / "extraction-parity-manifest.json"
BASELINE = EVIDENCE / "baseline"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def resolved_args(values: list[str], output: Path) -> list[str]:
    return [str(output / value.removeprefix("{output}/")) if value.startswith("{output}/") else value for value in values]


def semantic_json(path: Path, source_fields: list[str]) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    for field in source_fields:
        parts = field.split(".")
        current = value
        for part in parts[:-1]:
            current = current[part]
        if parts[-1] not in current:
            raise ValueError(f"missing predeclared source field {field} in {path}")
        del current[parts[-1]]
    return value


def semantic_markdown(path: Path, provenance_prefix: str) -> str:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    matches = [line for line in lines if line.startswith(provenance_prefix)]
    if len(matches) != 1:
        raise ValueError(f"expected one source-provenance line in {path}, found {len(matches)}")
    return "".join(line for line in lines if not line.startswith(provenance_prefix))


def run_command(command: list[str], environment: dict[str, str]) -> int:
    completed = subprocess.run(command, cwd=ROOT, env=environment, capture_output=True, text=True, check=False)
    if completed.returncode != 0:
        print(f"failed command: {' '.join(command)}")
        print(completed.stdout[-3000:])
        print(completed.stderr[-3000:])
    return completed.returncode


def compare_output(name: str, current: Path, baseline: Path, manifest: dict) -> None:
    policy = manifest["predeclared_comparison"]
    if name in policy["byte_equal"]:
        if current.read_bytes() != baseline.read_bytes():
            raise ValueError(f"byte parity failed: {name}")
    elif name in {"causal.json", "longitudinal.json"}:
        fields = policy["causal_and_longitudinal_json_source_fields_allowed_to_differ"]
        if semantic_json(current, fields) != semantic_json(baseline, fields):
            raise ValueError(f"semantic JSON parity failed: {name}")
    elif name == "causal.md":
        prefix = policy["causal_markdown_provenance_line_prefix"]
        if semantic_markdown(current, prefix) != semantic_markdown(baseline, prefix):
            raise ValueError("causal Markdown parity failed")
    elif name == "longitudinal.md":
        prefix = policy["longitudinal_markdown_provenance_line_prefix"]
        if semantic_markdown(current, prefix) != semantic_markdown(baseline, prefix):
            raise ValueError("longitudinal Markdown parity failed")
    elif name in {"causal-timing.json", "longitudinal-timing.json"}:
        # Deliberately retained raw and excluded from semantic equality.
        json.loads(current.read_text(encoding="utf-8"))
    else:
        raise ValueError(f"artifact lacks a predeclared comparison: {name}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    output = args.output_dir.resolve()
    if output == BASELINE.resolve() or BASELINE.resolve() in output.parents:
        parser.error("candidate output cannot overwrite the frozen baseline")
    output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if manifest.get("status") != "frozen-before-source-edits":
        raise SystemExit("parity manifest is not frozen")

    environment = os.environ.copy()
    environment["LEAFREADER_VOCABULARY_EVALUATOR_BUILD_DIR"] = str(ROOT / ".build/vocabulary-extraction-candidate")
    environment["LEAFREADER_VOCABULARY_POS_BUILD_DIR"] = str(ROOT / ".build/vocabulary-pos-extraction-candidate")
    results = []
    for run in manifest["runs"]:
        command = resolved_args(run["command"], output)
        exit_status = run_command(command, environment)
        if exit_status != run["expected_exit_status"]:
            raise SystemExit(f"{run['id']}: exit {exit_status}, expected {run['expected_exit_status']}")
        validator = resolved_args(run["validator"], output)
        validator_status = run_command(validator, environment)
        if validator_status != run["validator_expected_exit_status"]:
            raise SystemExit(f"{run['id']}: validator exit {validator_status}")
        artifacts = []
        for name, expected in run["output_sha256"].items():
            old = BASELINE / name
            if sha256(old) != expected:
                raise SystemExit(f"frozen baseline artifact changed: {name}")
            current = output / name
            if not current.is_file():
                raise SystemExit(f"{run['id']}: missing output {name}")
            compare_output(name, current, old, manifest)
            artifacts.append({"name": name, "baseline_sha256": expected, "candidate_sha256": sha256(current)})
        results.append({"id": run["id"], "exit_status": exit_status, "validator_exit_status": validator_status, "artifacts": artifacts})
        print(f"{run['id']}: semantic parity passed ({len(artifacts)} artifacts)")

    report = {
        "schema_version": 1,
        "baseline_manifest_sha256": sha256(MANIFEST),
        "status": "PASS",
        "runs": results,
        "timing_policy": manifest["predeclared_comparison"]["timing_json"],
    }
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("vocabulary extraction parity passed")


if __name__ == "__main__":
    main()
