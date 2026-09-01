#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leafreader-domain-builder-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

printf 'alpha_NOUN\t2000,5,1\nbeta\t2000,10,1\n123\t2000,100,1\n' | gzip > "$TEMP_DIR/first.gz"
printf 'alpha_VERB\t2001,20,1\ngamma\t2001,15,1\n' | gzip > "$TEMP_DIR/second.gz"
first_md5="$(md5 -q "$TEMP_DIR/first.gz")"
second_md5="$(md5 -q "$TEMP_DIR/second.gz")"

LEAFREADER_GOOGLE_BOOKS_WORKERS=2 \
LEAFREADER_GOOGLE_BOOKS_CACHE_DIR="$TEMP_DIR/cache" \
  "$ROOT_DIR/scripts/build_google_books_domain_resource.sh" \
  "$TEMP_DIR/result.sqlite" 3 \
  "file://$TEMP_DIR/first.gz" "$first_md5" \
  "file://$TEMP_DIR/second.gz" "$second_md5" >/dev/null

actual="$(sqlite3 -separator ':' "$TEMP_DIR/result.sqlite" \
  'SELECT word_key, rank FROM word_rank ORDER BY rank')"
expected=$'alpha:1\ngamma:2\nbeta:3'
if [[ "$actual" != "$expected" ]]; then
  echo "cross-shard aggregation/ranking mismatch" >&2
  printf 'expected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
  exit 1
fi

if LEAFREADER_GOOGLE_BOOKS_CACHE_DIR="$TEMP_DIR/bad-cache" \
  "$ROOT_DIR/scripts/build_google_books_domain_resource.sh" \
  "$TEMP_DIR/invalid.sqlite" 3 \
  "file://$TEMP_DIR/first.gz" 00000000000000000000000000000000 >/dev/null 2>&1; then
  echo "builder unexpectedly accepted an invalid source checksum" >&2
  exit 1
fi

echo "vocabulary domain resource builder tests passed"
