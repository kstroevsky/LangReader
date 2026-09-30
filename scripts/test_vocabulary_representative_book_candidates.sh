#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leafreader-representative-books.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

xcrun swiftc \
  -warnings-as-errors \
  -framework PDFKit \
  -framework NaturalLanguage \
  -framework CryptoKit \
  "$ROOT_DIR/scripts/build_vocabulary_representative_book_candidates.swift" \
  -o "$TMP_DIR/build-vocabulary-representative-book-candidates"

"$TMP_DIR/build-vocabulary-representative-book-candidates" --self-test
