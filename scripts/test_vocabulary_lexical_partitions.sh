#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leafreader-lexical-partitions.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
FIXTURE="$ROOT_DIR/Tests/Fixtures/VocabularyLexicalPartition/policy-v1.json"

for run in first second; do
  "$ROOT_DIR/scripts/evaluate_vocabulary_lexical_partitions.sh" "$FIXTURE" "$TEMP_DIR/$run.json"
done
cmp "$TEMP_DIR/first.json" "$TEMP_DIR/second.json"

python3 - "$TEMP_DIR/first.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    report = json.load(handle)

metrics = report["metrics"]
assert metrics["anchorCount"] == 7
assert metrics["occurrenceCount"] == 22
assert metrics["resolvedOccurrenceCount"] == 13
assert metrics["predictedSplitCount"] == 2
assert metrics["correctPredictedSplitCount"] == 2
assert metrics["splitPrecision"] == 1
assert metrics["b3"]["f1"] == 1
assert report["unavailableNLPSplitCount"] == 0
assert report["splitPrecisionGate"]["passed"] is False
assert report["automaticSplitSafetyGatePassed"] is False
assert [point["minimumSplitOccurrenceSupport"] for point in report["riskCoverageCurve"]] == [2, 3, 4]
PY

echo "vocabulary lexical partition fixture tests passed"
