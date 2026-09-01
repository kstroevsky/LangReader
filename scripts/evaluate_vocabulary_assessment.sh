#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${LEAFREADER_VOCABULARY_EVALUATOR_BUILD_DIR:-$ROOT_DIR/.build/vocabulary-evaluator}"
EXECUTABLE="$BUILD_DIR/evaluate-vocabulary-assessment"
CORE_LIBRARY="$BUILD_DIR/libLeafReaderCore.a"
mkdir -p "$BUILD_DIR"

export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache"
export SWIFT_MODULECACHE_PATH="$BUILD_DIR/module-cache"

if [[ ! -f "$CORE_LIBRARY" ]] || find \
  "$ROOT_DIR/Sources/LeafReaderCore" \
  "$ROOT_DIR/scripts/build_core_module.sh" \
  -type f -newer "$CORE_LIBRARY" -print -quit | grep -q .; then
  "$ROOT_DIR/scripts/build_core_module.sh" "$BUILD_DIR" -O >/dev/null
fi

if [[ ! -x "$EXECUTABLE" ]] \
  || [[ "$ROOT_DIR/scripts/evaluate_vocabulary_assessment.swift" -nt "$EXECUTABLE" ]] \
  || [[ "$CORE_LIBRARY" -nt "$EXECUTABLE" ]]; then
  swiftc \
    -O \
    -parse-as-library \
    -package-name LeafReader \
    -I "$BUILD_DIR" \
    -L "$BUILD_DIR" \
    -lLeafReaderCore \
    "$ROOT_DIR/scripts/evaluate_vocabulary_assessment.swift" \
    -o "$EXECUTABLE"
fi

"$EXECUTABLE" "$@"
