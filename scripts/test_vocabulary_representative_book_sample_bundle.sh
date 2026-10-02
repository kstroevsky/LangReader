#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leafreader-representative-bundle.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

"$ROOT_DIR/scripts/build_core_module.sh" "$TMP_DIR" -O -warnings-as-errors >/dev/null

xcrun swiftc \
  -swift-version 6 \
  -parse-as-library \
  -package-name LeafReader \
  -warnings-as-errors \
  -I "$TMP_DIR" -L "$TMP_DIR" -lLeafReaderCore \
  -framework PDFKit \
  -framework CryptoKit \
  "$ROOT_DIR/scripts/representative_book_source_support.swift" \
  "$ROOT_DIR/scripts/build_vocabulary_representative_book_sample_bundle.swift" \
  -o "$TMP_DIR/build-vocabulary-representative-book-sample-bundle"

test -x "$TMP_DIR/build-vocabulary-representative-book-sample-bundle"
echo "representative book sample bundle builder compile test passed"
