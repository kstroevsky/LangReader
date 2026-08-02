#!/usr/bin/env bash
# Builds `LeafReaderCore` as a real Swift module plus a static library.
#
# Both the app build and the logic tests compile against the *module*, not
# against the core's source files. That is the point of Phase 0.1: the compiler,
# not a naming convention, decides what the core is allowed to reach. A core
# file that starts using AppKit fails here, before anything downstream runs.
#
# Usage: build_core_module.sh <out-dir> [<target-triple>] [extra swiftc flags...]
#
# Emits <out-dir>/LeafReaderCore.swiftmodule and <out-dir>/libLeafReaderCore.a.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CORE_SOURCE_ROOT="$ROOT_DIR/Sources/LeafReaderCore"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <out-dir> [<target-triple>] [extra swiftc flags...]" >&2
  exit 2
fi

OUT_DIR="$1"
shift
TARGET_TRIPLE=""
if [[ $# -gt 0 && "$1" != -* ]]; then
  TARGET_TRIPLE="$1"
  shift
fi

CORE_SOURCES=()
while IFS= read -r source; do
  CORE_SOURCES+=("$source")
done < <(find "$CORE_SOURCE_ROOT" -type f -name '*.swift' -print | LC_ALL=C sort)

if [[ "${#CORE_SOURCES[@]}" -eq 0 ]]; then
  echo "No Swift sources found under $CORE_SOURCE_ROOT" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

TARGET_FLAGS=()
if [[ -n "$TARGET_TRIPLE" ]]; then
  TARGET_FLAGS=(-target "$TARGET_TRIPLE")
fi

# The core is built in Swift 6 language mode while the app is still Swift 5.
# Keeping that split here means the strictness applies to the core wherever it
# is built, not only under SwiftPM.
swiftc \
  -module-name LeafReaderCore \
  -package-name LeafReader \
  -swift-version 6 \
  -emit-module \
  -emit-module-path "$OUT_DIR/LeafReaderCore.swiftmodule" \
  -emit-library -static \
  -o "$OUT_DIR/libLeafReaderCore.a" \
  ${TARGET_FLAGS[@]+"${TARGET_FLAGS[@]}"} \
  "$@" \
  "${CORE_SOURCES[@]}"
