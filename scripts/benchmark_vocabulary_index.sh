#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leafreader-index-benchmark.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache"
export SWIFT_MODULECACHE_PATH="$BUILD_DIR/module-cache"

"$ROOT_DIR/scripts/build_core_module.sh" "$BUILD_DIR" >/dev/null
swiftc \
  -O \
  -parse-as-library \
  -package-name LeafReader \
  -I "$BUILD_DIR" \
  -L "$BUILD_DIR" \
  -lLeafReaderCore \
  "$ROOT_DIR/scripts/benchmark_vocabulary_index.swift" \
  -framework NaturalLanguage \
  -o "$BUILD_DIR/benchmark-vocabulary-index"

"$BUILD_DIR/benchmark-vocabulary-index" "${1:-300}" "${2:-2000}" "${3:-5}"
