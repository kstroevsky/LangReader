#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${LEAFREADER_REPRESENTATIVE_BOOK_BUILD_DIR:-$ROOT_DIR/.build/vocabulary-representative-book}"
EXECUTABLE="$BUILD_DIR/materialize-vocabulary-representative-book-fixture"
CORE_LIBRARY="$BUILD_DIR/libLeafReaderCore.a"
mkdir -p "$BUILD_DIR"

if [[ ! -f "$CORE_LIBRARY" ]] || find "$ROOT_DIR/Sources/LeafReaderCore" -type f -newer "$CORE_LIBRARY" -print -quit | grep -q .; then
  "$ROOT_DIR/scripts/build_core_module.sh" "$BUILD_DIR" -O -warnings-as-errors >/dev/null
fi

swiftc -O -warnings-as-errors -swift-version 6 -parse-as-library -package-name LeafReader \
  -I "$BUILD_DIR" -L "$BUILD_DIR" -lLeafReaderCore \
  -framework PDFKit \
  "$ROOT_DIR/scripts/representative_book_source_support.swift" \
  "$ROOT_DIR/scripts/materialize_vocabulary_representative_book_fixture.swift" \
  -o "$EXECUTABLE"

"$EXECUTABLE" --self-test
