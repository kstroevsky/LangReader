#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leafreader-vocabulary-benchmark.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache"
export SWIFT_MODULECACHE_PATH="$BUILD_DIR/module-cache"

"$ROOT_DIR/scripts/build_core_module.sh" "$BUILD_DIR" >/dev/null
swiftc \
  -O \
  -package-name LeafReader \
  -I "$BUILD_DIR" \
  -L "$BUILD_DIR" \
  -lLeafReaderCore \
  "$ROOT_DIR/scripts/benchmark_vocabulary_storage.swift" \
  "$ROOT_DIR/Sources/LeafReaderApp/VocabularyReview/PDFWordRecordStore.swift" \
  "$ROOT_DIR/Sources/LeafReaderApp/VocabularyReview/WebWordRecordStore.swift" \
  "$ROOT_DIR/Sources/LeafReaderApp/VocabularyReview/WordRecordSQLiteRowMapper.swift" \
  "$ROOT_DIR/Sources/LeafReaderApp/VocabularyReview/WordRecordSQLiteStore.swift" \
  "$ROOT_DIR/Sources/LeafReaderApp/VocabularyReview/GermanFlexionStore.swift" \
  -framework Cocoa \
  -framework PDFKit \
  -lsqlite3 \
  -o "$BUILD_DIR/benchmark-vocabulary-storage"

"$BUILD_DIR/benchmark-vocabulary-storage" "${1:-2000}" "${2:-3}"
