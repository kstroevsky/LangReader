#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${LEAFREADER_VOCABULARY_MODEL_BUILD_DIR:-$ROOT_DIR/.build/vocabulary-observation-model}"
EXECUTABLE="$BUILD_DIR/generate-vocabulary-observation-model"
CORE_LIBRARY="$BUILD_DIR/libLeafReaderCore.a"

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <output.json|->" >&2
  exit 2
fi

mkdir -p "$BUILD_DIR"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache"
export SWIFT_MODULECACHE_PATH="$BUILD_DIR/module-cache"

if [[ ! -f "$CORE_LIBRARY" ]] || find \
  "$ROOT_DIR/Sources/LeafReaderCore" \
  "$ROOT_DIR/scripts/build_core_module.sh" \
  -type f -newer "$CORE_LIBRARY" -print -quit | grep -q .; then
  "$ROOT_DIR/scripts/build_core_module.sh" "$BUILD_DIR" >/dev/null
fi

if [[ ! -x "$EXECUTABLE" ]] \
  || [[ "$ROOT_DIR/scripts/generate_vocabulary_observation_model.swift" -nt "$EXECUTABLE" ]] \
  || [[ "$CORE_LIBRARY" -nt "$EXECUTABLE" ]]; then
  swiftc \
    -parse-as-library \
    -package-name LeafReader \
    -I "$BUILD_DIR" \
    -L "$BUILD_DIR" \
    -lLeafReaderCore \
    "$ROOT_DIR/scripts/generate_vocabulary_observation_model.swift" \
    -o "$EXECUTABLE"
fi

"$EXECUTABLE" "$1"
