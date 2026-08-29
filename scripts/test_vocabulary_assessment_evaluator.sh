#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leafreader-vocabulary-evaluator-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

python3 "$ROOT_DIR/scripts/validate_vocabulary_assessment_report.py" \
  "$ROOT_DIR/scripts/fixtures/vocabulary-assessment-valid.json" >/dev/null
if python3 "$ROOT_DIR/scripts/validate_vocabulary_assessment_report.py" \
  "$ROOT_DIR/scripts/fixtures/vocabulary-assessment-invalid.json" >/dev/null 2>&1; then
  echo "invalid vocabulary assessment fixture unexpectedly passed" >&2
  exit 1
fi

for run in first second; do
  "$ROOT_DIR/scripts/evaluate_vocabulary_assessment.sh" \
    --seed 42 \
    --readers 1 \
    --lemmas 20 \
    --no-gate \
    --json "$TEMP_DIR/$run.json" \
    --markdown "$TEMP_DIR/$run.md" >/dev/null
done
cmp "$TEMP_DIR/first.json" "$TEMP_DIR/second.json"
cmp "$TEMP_DIR/first.md" "$TEMP_DIR/second.md"
python3 "$ROOT_DIR/scripts/validate_vocabulary_assessment_report.py" "$TEMP_DIR/first.json" >/dev/null
python3 "$ROOT_DIR/scripts/run_vocabulary_assessment_sensitivity.py" --self-test >/dev/null
python3 "$ROOT_DIR/scripts/run_vocabulary_assessment_diagnostic_matrix.py" --self-test >/dev/null
echo "vocabulary assessment evaluator tests passed"
