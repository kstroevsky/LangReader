#!/bin/bash
# Proves that the platform-neutral core actually is platform-neutral, by asking
# the compiler rather than by inspecting file names.
#
# There are two populations here, and they are checked differently:
#
#   * `Sources/LeafReaderCore` — already a real module. Its compilation is proved
#     by `scripts/build_core_module.sh`, which every build and test run goes
#     through, so this script only has to enforce the import ban on it.
#   * `scripts/core_portable_files.txt` — framework-free files that intentionally
#     remain in the app target. The probe proves they can be reused by a future
#     platform; it does not decide that they belong in the domain Core.
#
# Why the compiler and not grep: 85 files that import no AppKit at all still
# could not compile standalone, because they referenced app-target types through
# the shared module. Nothing short of a real compile finds that.
#
# Three ways this fails, all of them useful:
#   * a core or candidate file gains a dependency on a UI framework;
#   * a candidate file gains a dependency on an app-target type;
#   * a listed file is deleted or renamed without updating the list.
#
# It also reports app files that may have become technically portable. Those
# files still require a domain-versus-presentation ownership decision.
#
#   0  the core and its candidates are portable
#   1  they are not
#   2  infrastructure problem (missing list, missing files)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 2

LIST="scripts/core_portable_files.txt"
readonly EXIT_NOT_PORTABLE=1
readonly EXIT_INFRASTRUCTURE=2

if [[ ! -f "$LIST" ]]; then
  echo "core portability: missing $LIST" >&2
  exit $EXIT_INFRASTRUCTURE
fi

# Read loop rather than `mapfile`: macOS ships bash 3.2, which has neither
# `mapfile` nor `readarray`.
CANDIDATE_FILES=()
while IFS= read -r line; do
  case "$line" in ''|\#*) continue ;; esac
  CANDIDATE_FILES+=("$line")
done < "$LIST"

# The core module's own sources, which are checked alongside the candidates.
MODULE_FILES=()
while IFS= read -r line; do
  MODULE_FILES+=("$line")
done < <(find Sources/LeafReaderCore -type f -name '*.swift' | LC_ALL=C sort)

if (( ${#MODULE_FILES[@]} == 0 )); then
  echo "core portability: no sources under Sources/LeafReaderCore" >&2
  exit $EXIT_INFRASTRUCTURE
fi

CORE_FILES=("${MODULE_FILES[@]}" ${CANDIDATE_FILES[@]+"${CANDIDATE_FILES[@]}"})

missing=0
for f in "${CORE_FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "core portability: listed file no longer exists: $f" >&2
    missing=1
  fi
done
if (( missing )); then
  echo "core portability: update $LIST after moving or deleting core files" >&2
  exit $EXIT_INFRASTRUCTURE
fi

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

# Half one: no core file may import a UI framework.
#
# This cannot be left to the compiler. swiftc resolves AppKit straight from the
# macOS SDK whether or not anything asks it to, so a core file can gain
# `import AppKit` and still compile standalone — the probe below stays green
# while the boundary is broken. Checking the import lines is exact: it is a
# statement about the text, not an inference about portability.
BANNED='^import (SwiftUI|AppKit|Cocoa|PDFKit|WebKit|Sparkle|UIKit)$'
if OFFENDERS="$(grep -lE "$BANNED" "${CORE_FILES[@]}" 2>/dev/null)"; then
  if [[ -n "$OFFENDERS" ]]; then
    echo >&2
    echo "core portability: FAILED - core files import a UI framework:" >&2
    while IFS= read -r f; do
      echo "  $f -> $(grep -oE "$BANNED" "$f" | tr '\n' ' ')" >&2
    done <<<"$OFFENDERS"
    echo >&2
    echo "Move the file out of $LIST, or lift the platform dependency behind a" >&2
    echo "protocol the core owns." >&2
    exit $EXIT_NOT_PORTABLE
  fi
fi

# Half two: the set must compile as a module on its own, which is what catches
# references to app-target types that no import line reveals.
echo "core portability: building the core module (${#MODULE_FILES[@]} files)"

if ! ./scripts/build_core_module.sh "$BUILD_DIR" >"$BUILD_DIR/core-build.txt" 2>&1; then
  echo >&2
  echo "core portability: FAILED - LeafReaderCore does not build." >&2
  echo >&2
  grep "error:" "$BUILD_DIR/core-build.txt" | head -25 >&2
  exit $EXIT_NOT_PORTABLE
fi

# The app files are compiled *against* the core module rather than alongside its
# sources, because some already `import LeafReaderCore`. Passing means they need
# nothing beyond Foundation and the core. That is a portability property, not a
# decision to move them into Core.
echo "core portability: compiling ${#CANDIDATE_FILES[@]} framework-free app files against it"

if ! swiftc -emit-module \
    -module-name LeafReaderCoreCandidates \
    -package-name LeafReader \
    -I "$BUILD_DIR" \
    -o "$BUILD_DIR/LeafReaderCoreCandidates.swiftmodule" \
    ${CANDIDATE_FILES[@]+"${CANDIDATE_FILES[@]}"} 2>"$BUILD_DIR/errors.txt"; then
  echo >&2
  echo "core portability: FAILED - the candidates do not compile without the UI frameworks." >&2
  echo >&2
  grep "error:" "$BUILD_DIR/errors.txt" | head -25 >&2
  echo >&2
  echo "If the dependency is presentation-specific, keep the file in the app and" >&2
  echo "remove it from $LIST. Otherwise, abstract the platform dependency behind" >&2
  echo "a narrow protocol; this check does not determine Core ownership." >&2
  exit $EXIT_NOT_PORTABLE
fi

echo "core portability: ok - ${#MODULE_FILES[@]} domain-core files, ${#CANDIDATE_FILES[@]} portable app files"

# Advisory only: files that import no UI framework and are not yet listed.
# Several may still fail for app-target references, and presentation files may
# be correctly placed in LeafReaderApp, so this never fails the check.
UNLISTED="$(comm -23 \
  <(find Sources/LeafReaderApp -name '*.swift' -type f | sort) \
  <(sort "$LIST") \
  | xargs grep -LE 'import SwiftUI|import AppKit|import Cocoa|import PDFKit|import WebKit|import Sparkle' 2>/dev/null | sort)"

if [[ -n "$UNLISTED" ]]; then
  count=$(wc -l <<<"$UNLISTED" | tr -d ' ')
  echo "core portability: $count more app files import no UI framework; classify them before adding them to this probe or Core"
fi
