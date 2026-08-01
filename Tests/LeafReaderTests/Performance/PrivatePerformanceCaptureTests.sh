#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leafreader-private-perf.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export CLANG_MODULE_CACHE_PATH="$TEST_DIR/module-cache"

mkdir -p "$TEST_DIR/private documents"
printf 'pdf fixture' >"$TEST_DIR/private documents/A Personal Book.pdf"
printf 'epub fixture' >"$TEST_DIR/private documents/Secret Notes.epub"
printf 'docx fixture' >"$TEST_DIR/private documents/Work Draft.docx"

MANIFEST="$TEST_DIR/manifest.json"
METADATA="$TEST_DIR/metadata.json"
cat >"$MANIFEST" <<JSON
{
  "schema_version": 1,
  "fixtures": [
    {"format": "pdf", "alias": "representative-large-pdf", "path": "$TEST_DIR/private documents/A Personal Book.pdf"},
    {"format": "epub", "alias": "representative-epub", "path": "$TEST_DIR/private documents/Secret Notes.epub"},
    {"format": "docx", "alias": "representative-docx", "path": "$TEST_DIR/private documents/Work Draft.docx"}
  ],
  "datasets": {
    "ai_conversation_messages": 240,
    "notes": 180,
    "vocabulary_records": 4200
  }
}
JSON

TOOL="$ROOT_DIR/scripts/private_perf_fixture_manifest.swift"
swift "$TOOL" validate "$MANIFEST"

PATHS="$(swift "$TOOL" paths "$MANIFEST")"
grep -Fq "$TEST_DIR/private documents/A Personal Book.pdf" <<<"$PATHS"
grep -Fq "$TEST_DIR/private documents/Secret Notes.epub" <<<"$PATHS"
grep -Fq "$TEST_DIR/private documents/Work Draft.docx" <<<"$PATHS"

swift "$TOOL" metadata "$MANIFEST" "$METADATA"
grep -Fq '"alias" : "representative-large-pdf"' "$METADATA"
grep -Fq '"vocabulary_records" : 4200' "$METADATA"
grep -Fq '"size_bytes"' "$METADATA"

if grep -Fq "$TEST_DIR" "$METADATA" || \
   grep -Fq 'A Personal Book' "$METADATA" || \
   grep -Fq 'Secret Notes' "$METADATA" || \
   grep -Fq 'Work Draft' "$METADATA"; then
  echo "Private performance metadata leaked a source path or filename" >&2
  exit 1
fi

INVALID="$TEST_DIR/invalid.json"
cat >"$INVALID" <<JSON
{
  "schema_version": 1,
  "fixtures": [
    {"format": "pdf", "alias": "only-pdf", "path": "$TEST_DIR/private documents/A Personal Book.pdf"}
  ],
  "datasets": {
    "ai_conversation_messages": 240,
    "notes": 180,
    "vocabulary_records": 4200
  }
}
JSON

if swift "$TOOL" validate "$INVALID" >/dev/null 2>&1; then
  echo "A manifest without EPUB and DOCX fixtures must be rejected" >&2
  exit 1
fi

echo "PrivatePerformanceCaptureTests passed"
