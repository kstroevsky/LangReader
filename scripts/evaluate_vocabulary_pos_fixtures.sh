#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${LEAFREADER_VOCABULARY_POS_BUILD_DIR:-$ROOT_DIR/.build/vocabulary-pos-evaluator}"
EXECUTABLE="$BUILD_DIR/evaluate-vocabulary-pos-fixtures"
CORE_LIBRARY="$BUILD_DIR/libLeafReaderCore.a"
VALIDATION_LIBRARY="$BUILD_DIR/libLeafReaderValidation.a"
mkdir -p "$BUILD_DIR"

if [[ ! -f "$CORE_LIBRARY" ]] || find "$ROOT_DIR/Sources/LeafReaderCore" -type f -newer "$CORE_LIBRARY" -print -quit | grep -q .; then
  "$ROOT_DIR/scripts/build_core_module.sh" "$BUILD_DIR" -O -warnings-as-errors >/dev/null
fi
if [[ ! -f "$VALIDATION_LIBRARY" ]] \
  || find "$ROOT_DIR/Sources/LeafReaderValidation" "$ROOT_DIR/scripts/build_validation_module.sh" \
    -type f -newer "$VALIDATION_LIBRARY" -print -quit | grep -q . \
  || [[ "$CORE_LIBRARY" -nt "$VALIDATION_LIBRARY" ]]; then
  "$ROOT_DIR/scripts/build_validation_module.sh" "$BUILD_DIR" -O >/dev/null
fi
if [[ ! -x "$EXECUTABLE" ]] || [[ "$ROOT_DIR/scripts/evaluate_vocabulary_pos_fixtures.swift" -nt "$EXECUTABLE" ]] \
  || [[ "$CORE_LIBRARY" -nt "$EXECUTABLE" ]] || [[ "$VALIDATION_LIBRARY" -nt "$EXECUTABLE" ]]; then
  swiftc -O -warnings-as-errors -swift-version 6 -parse-as-library -package-name LeafReader \
    -I "$BUILD_DIR" -L "$BUILD_DIR" -lLeafReaderValidation -lLeafReaderCore \
    "$ROOT_DIR/scripts/evaluate_vocabulary_pos_fixtures.swift" -o "$EXECUTABLE"
fi
"$EXECUTABLE" "$@"
