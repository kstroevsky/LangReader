#!/usr/bin/env bash
# Build the internal validation module for standalone Swift evaluator wrappers.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VALIDATION_SOURCE_ROOT="$ROOT_DIR/Sources/LeafReaderValidation"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <out-dir> [extra swiftc flags...]" >&2
  exit 2
fi

OUT_DIR="$1"
shift
if [[ ! -f "$OUT_DIR/LeafReaderCore.swiftmodule" ]]; then
  echo "LeafReaderCore module is missing from $OUT_DIR" >&2
  exit 1
fi

VALIDATION_SOURCES=()
while IFS= read -r source; do
  VALIDATION_SOURCES+=("$source")
done < <(find "$VALIDATION_SOURCE_ROOT" -type f -name '*.swift' -print | LC_ALL=C sort)
if [[ ${#VALIDATION_SOURCES[@]} -eq 0 ]]; then
  echo "No validation Swift sources found" >&2
  exit 1
fi

swiftc \
  -module-name LeafReaderValidation \
  -package-name LeafReader \
  -swift-version 6 \
  -warnings-as-errors \
  -emit-module \
  -emit-module-path "$OUT_DIR/LeafReaderValidation.swiftmodule" \
  -emit-library -static \
  -o "$OUT_DIR/libLeafReaderValidation.a" \
  -I "$OUT_DIR" \
  "$@" \
  "${VALIDATION_SOURCES[@]}"
