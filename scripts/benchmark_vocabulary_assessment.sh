#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${LEAFREADER_VOCABULARY_BENCHMARK_BUILD_DIR:-$ROOT_DIR/.build/vocabulary-assessment-benchmark}"
EXECUTABLE="$BUILD_DIR/benchmark-vocabulary-assessment"
CORE_LIBRARY="$BUILD_DIR/libLeafReaderCore.a"
OUTPUT_PATH="${1:-$ROOT_DIR/docs/perf/vocabulary-assessment-benchmark.json}"
mkdir -p "$BUILD_DIR"

export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache"
export SWIFT_MODULECACHE_PATH="$BUILD_DIR/module-cache"
SOURCE_REVISION="$(git -C "$ROOT_DIR" rev-parse HEAD)"
if ! git -C "$ROOT_DIR" diff --quiet HEAD -- Sources scripts/benchmark_vocabulary_assessment.swift; then
  SOURCE_REVISION="$SOURCE_REVISION+dirty"
fi
export LEAFREADER_BENCHMARK_SOURCE_REVISION="$SOURCE_REVISION"
export LEAFREADER_BENCHMARK_SWIFT_VERSION="$(swift --version 2>&1 | head -1)"

if [[ ! -f "$CORE_LIBRARY" ]] || find \
  "$ROOT_DIR/Sources/LeafReaderCore" \
  "$ROOT_DIR/scripts/build_core_module.sh" \
  -type f -newer "$CORE_LIBRARY" -print -quit | grep -q .; then
  "$ROOT_DIR/scripts/build_core_module.sh" "$BUILD_DIR" -O >/dev/null
fi

if [[ ! -x "$EXECUTABLE" ]] \
  || [[ "$ROOT_DIR/scripts/benchmark_vocabulary_assessment.swift" -nt "$EXECUTABLE" ]] \
  || [[ "$CORE_LIBRARY" -nt "$EXECUTABLE" ]]; then
  swiftc \
    -O \
    -parse-as-library \
    -package-name LeafReader \
    -I "$BUILD_DIR" \
    -L "$BUILD_DIR" \
    -lLeafReaderCore \
    "$ROOT_DIR/scripts/benchmark_vocabulary_assessment.swift" \
    -o "$EXECUTABLE"
fi

"$EXECUTABLE" "$OUTPUT_PATH"
