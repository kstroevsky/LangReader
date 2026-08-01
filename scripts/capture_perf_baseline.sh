#!/usr/bin/env bash
# Captures a performance baseline by driving the real app.
#
# The app records nothing unless LEAFVOCAB_PERF=1, and writes the report to
# LEAFVOCAB_PERF_OUT on quit. This script launches the built bundle with those
# set, opens fixtures through Launch Services (so the normal app-open path runs),
# quits cleanly so `applicationWillTerminate` flushes the report, and prints it.
#
# Synthetic mode captures launch, main window, PDF open, first-page display,
# and theme apply. Private mode validates representative PDF/EPUB/DOCX fixtures,
# opens all of them, pauses for the database-backed and AI surfaces, and writes
# a path-free metadata sidecar next to the aggregate report.
#
#   scripts/capture_perf_baseline.sh <fixtures-dir> [<out-basepath>]
#   scripts/capture_perf_baseline.sh --private-manifest <manifest.json> [<out-basepath>]
#
# <fixtures-dir> must contain small.pdf and large.pdf (see make_perf_fixtures.swift).
# The private manifest must remain uncommitted; copy docs/perf/private-fixtures.example.json.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Leaf Vocabulary"
APP_BINARY="$ROOT_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"
MANIFEST_TOOL="$ROOT_DIR/scripts/private_perf_fixture_manifest.swift"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/private/tmp/leafreader-clang-cache}"

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <fixtures-dir> [<out-basepath>]" >&2
  echo "       $0 --private-manifest <manifest.json> [<out-basepath>]" >&2
  exit 2
fi

PRIVATE_MODE=0
FIXTURE_FILES=()
PRIVATE_MANIFEST=""
if [[ "$1" == "--private-manifest" ]]; then
  if [[ $# -lt 2 ]]; then
    echo "--private-manifest requires a manifest path" >&2
    exit 2
  fi
  PRIVATE_MODE=1
  PRIVATE_MANIFEST="$2"
  OUT_BASE="${3:-$ROOT_DIR/docs/perf/representative-baseline}"
  swift "$MANIFEST_TOOL" validate "$PRIVATE_MANIFEST"
  while IFS= read -r fixture; do
    FIXTURE_FILES+=("$fixture")
  done < <(swift "$MANIFEST_TOOL" paths "$PRIVATE_MANIFEST")
else
  FIXTURES_DIR="$1"
  OUT_BASE="${2:-$ROOT_DIR/docs/perf/baseline}"
  for name in small.pdf large.pdf; do
    if [[ ! -f "$FIXTURES_DIR/$name" ]]; then
      echo "Missing fixture $FIXTURES_DIR/$name — run scripts/make_perf_fixtures.swift." >&2
      exit 2
    fi
    FIXTURE_FILES+=("$FIXTURES_DIR/$name")
  done
fi

if [[ ! -x "$APP_BINARY" ]]; then
  echo "No built app at $APP_BINARY — run scripts/build_app.sh first." >&2
  exit 2
fi
mkdir -p "$(dirname "$OUT_BASE")"

quit_app() { osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true; }
wait_gone() {
  for _ in $(seq 1 50); do pgrep -x "$APP_NAME" >/dev/null || return 0; sleep 0.2; done
}

echo "==> Stopping any running instance"
quit_app; wait_gone

echo "==> Launching with performance capture enabled"
LEAFVOCAB_PERF=1 LEAFVOCAB_PERF_OUT="$OUT_BASE" "$APP_BINARY" >/dev/null 2>&1 &
APP_PID=$!
# Give it time to finish launching and lay out the main window.
for _ in $(seq 1 40); do
  osascript -e "tell application \"$APP_NAME\" to exists" >/dev/null 2>&1 && break
  sleep 0.25
done
sleep 2

open_fixture() {
  local file="$1"
  echo "==> Opening $(basename "$file")"
  /usr/bin/open -a "$ROOT_DIR/$APP_NAME.app" "$file"
  sleep 3
}

for fixture in "${FIXTURE_FILES[@]}"; do
  open_fixture "$fixture"
done
# A second pass gives every format more than one sample and exercises its warm path.
for fixture in "${FIXTURE_FILES[@]}"; do
  open_fixture "$fixture"
done

if [[ "$PRIVATE_MODE" == "1" ]]; then
  if [[ ! -t 0 ]]; then
    echo "Private capture needs an interactive terminal for its manual surface checkpoint." >&2
    echo "Open Shelf, Notes, Vocabulary Library, a long AI conversation, and selection tools, then run this command in Terminal." >&2
    quit_app
    wait "$APP_PID" 2>/dev/null || true
    exit 2
  fi
  echo
  echo "==> Exercise the representative data surfaces now"
  echo "    Open Shelf, Notes, Vocabulary Library, a long AI conversation,"
  echo "    selection tools, and switch theme. Press Return when complete."
  read -r
fi

echo "==> Quitting (flushes the baseline)"
quit_app
wait "$APP_PID" 2>/dev/null || true
wait_gone

if [[ -f "$OUT_BASE.txt" ]]; then
  if [[ "$PRIVATE_MODE" == "1" ]]; then
    swift "$MANIFEST_TOOL" metadata "$PRIVATE_MANIFEST" "$OUT_BASE.fixtures.json"
  fi
  echo
  echo "Captured baseline ($OUT_BASE.txt):"
  echo
  cat "$OUT_BASE.txt"
  echo
  echo "JSON written to $OUT_BASE.json"
  if [[ "$PRIVATE_MODE" == "1" ]]; then
    echo "Path-free fixture metadata written to $OUT_BASE.fixtures.json"
  fi
else
  echo "No baseline written — the app did not flush $OUT_BASE.txt." >&2
  exit 1
fi
