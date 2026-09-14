#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${LEAFREADER_VOCABULARY_POS_BUILD_DIR:-$ROOT_DIR/.build/vocabulary-pos-evaluator}"
EXECUTABLE="$BUILD_DIR/evaluate-vocabulary-pos-fixtures"
CORE_LIBRARY="$BUILD_DIR/libLeafReaderCore.a"
mkdir -p "$BUILD_DIR"

if [[ ! -f "$CORE_LIBRARY" ]] || find "$ROOT_DIR/Sources/LeafReaderCore" -type f -newer "$CORE_LIBRARY" -print -quit | grep -q .; then
  "$ROOT_DIR/scripts/build_core_module.sh" "$BUILD_DIR" -O >/dev/null
fi
if [[ ! -x "$EXECUTABLE" ]] || [[ "$ROOT_DIR/scripts/evaluate_vocabulary_pos_fixtures.swift" -nt "$EXECUTABLE" ]] || [[ "$CORE_LIBRARY" -nt "$EXECUTABLE" ]]; then
  swiftc -O -warnings-as-errors -swift-version 6 -parse-as-library -package-name LeafReader \
    -I "$BUILD_DIR" -L "$BUILD_DIR" -lLeafReaderCore \
    "$ROOT_DIR/scripts/evaluate_vocabulary_pos_fixtures.swift" -o "$EXECUTABLE"
fi
"$EXECUTABLE" "$@"
