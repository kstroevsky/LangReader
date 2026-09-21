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
"$ROOT_DIR/scripts/evaluate_vocabulary_assessment.sh" --causal-self-test >/dev/null
"$ROOT_DIR/scripts/evaluate_vocabulary_assessment.sh" \
  --seed 7 \
  --readers 1 \
  --lemmas 20 \
  --no-gate \
  --json "$TEMP_DIR/causal-standard.json" \
  --markdown "$TEMP_DIR/causal-standard.md" \
  --causal-manifest "$ROOT_DIR/scripts/fixtures/vocabulary-causal-diagnostic-manifest-v1.json" \
  --causal-json "$TEMP_DIR/causal.json" \
  --causal-markdown "$TEMP_DIR/causal.md" \
  --causal-timing "$TEMP_DIR/causal-timing.json" >/dev/null
"$ROOT_DIR/scripts/evaluate_vocabulary_assessment.sh" \
  --seed 7 \
  --readers 1 \
  --lemmas 20 \
  --no-gate \
  --json "$TEMP_DIR/causal-standard-repeat.json" \
  --markdown "$TEMP_DIR/causal-standard-repeat.md" \
  --causal-manifest "$ROOT_DIR/scripts/fixtures/vocabulary-causal-diagnostic-manifest-v1.json" \
  --causal-json "$TEMP_DIR/causal-repeat.json" \
  --causal-markdown "$TEMP_DIR/causal-repeat.md" \
  --causal-timing "$TEMP_DIR/causal-timing-repeat.json" >/dev/null
cmp "$TEMP_DIR/causal.json" "$TEMP_DIR/causal-repeat.json"
cmp "$TEMP_DIR/causal.md" "$TEMP_DIR/causal-repeat.md"
python3 "$ROOT_DIR/scripts/validate_vocabulary_causal_diagnostic_report.py" "$TEMP_DIR/causal.json" >/dev/null
python3 "$ROOT_DIR/scripts/validate_vocabulary_causal_diagnostic_report.py" \
  "$TEMP_DIR/causal.json" --self-test >/dev/null
"$ROOT_DIR/scripts/evaluate_vocabulary_assessment.sh" --longitudinal-self-test >/dev/null
for run in longitudinal-first longitudinal-second; do
  "$ROOT_DIR/scripts/evaluate_vocabulary_assessment.sh" \
    --seed 7 \
    --readers 1 \
    --lemmas 20 \
    --no-gate \
    --json "$TEMP_DIR/$run-standard.json" \
    --markdown "$TEMP_DIR/$run-standard.md" \
    --longitudinal-manifest "$ROOT_DIR/scripts/fixtures/vocabulary-longitudinal-diagnostic-manifest-v1.json" \
    --longitudinal-json "$TEMP_DIR/$run.json" \
    --longitudinal-markdown "$TEMP_DIR/$run.md" \
    --longitudinal-timing "$TEMP_DIR/$run-timing.json" >/dev/null
done
cmp "$TEMP_DIR/longitudinal-first.json" "$TEMP_DIR/longitudinal-second.json"
cmp "$TEMP_DIR/longitudinal-first.md" "$TEMP_DIR/longitudinal-second.md"
python3 "$ROOT_DIR/scripts/validate_vocabulary_longitudinal_report.py" \
  "$TEMP_DIR/longitudinal-first.json" --self-test >/dev/null
echo "vocabulary assessment evaluator tests passed"
