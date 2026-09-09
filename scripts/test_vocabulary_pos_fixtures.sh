#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leafreader-pos-fixtures.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
FIXTURE="$ROOT_DIR/Tests/Fixtures/VocabularyPOS/ud-v2.18-selected.json"

for run in first second; do
  "$ROOT_DIR/scripts/evaluate_vocabulary_pos_fixtures.sh" "$FIXTURE" "$TEMP_DIR/$run.json"
done
cmp "$TEMP_DIR/first.json" "$TEMP_DIR/second.json"
python3 "$ROOT_DIR/scripts/validate_vocabulary_pos_report.py" "$FIXTURE" "$TEMP_DIR/first.json" --self-test >/dev/null
echo "vocabulary POS fixture tests passed"
