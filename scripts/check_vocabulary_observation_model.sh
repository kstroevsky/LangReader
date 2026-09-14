#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="$ROOT_DIR/scripts/fixtures/vocabulary-observation-model-v1.json"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leafreader-vocabulary-observation.XXXXXX")"
trap 'rm -r "$TEMP_DIR"' EXIT

"$ROOT_DIR/scripts/generate_vocabulary_observation_model.sh" "$TEMP_DIR/generated.json"
if ! cmp "$TEMP_DIR/generated.json" "$FIXTURE"; then
  echo "vocabulary observation-model fixture is stale" >&2
  echo "regenerate it from VocabularyObservationModel before committing" >&2
  exit 1
fi

python3 "$ROOT_DIR/scripts/fit_vocabulary_calibration.py" \
  --observation-manifest "$FIXTURE" \
  --self-test

cp "$FIXTURE" "$TEMP_DIR/corrupt-golden.json"
perl -0pi -e 's/"evidenceLikelihood" : 0\.5/"evidenceLikelihood" : 0.51/' \
  "$TEMP_DIR/corrupt-golden.json"
if python3 "$ROOT_DIR/scripts/fit_vocabulary_calibration.py" \
  --observation-manifest "$TEMP_DIR/corrupt-golden.json" \
  --self-test >/dev/null 2>&1; then
  echo "calibration fitter unexpectedly accepted a corrupt Core golden fixture" >&2
  exit 1
fi

echo "vocabulary observation model and calibration fitter are coherent"
