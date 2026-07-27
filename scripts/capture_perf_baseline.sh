#!/usr/bin/env bash
# Captures a performance baseline by driving the real app.
#
# The app records nothing unless LEAFVOCAB_PERF=1, and writes the report to
# LEAFVOCAB_PERF_OUT on quit. This script launches the built bundle with those
# set, opens the fixture PDFs through Apple Events (so `loadPDF` runs exactly as
# it does for a user), quits cleanly so `applicationWillTerminate` flushes the
# report, and prints it.
#
# What this captures on any machine: launch, main window, PDF open, first-page
# display, and the theme apply that rides a document open. Web (EPUB/DOCX), the
# AI surfaces, and Notes need a fixture / a configured model and are captured by
# pointing the app at them by hand with the same two environment variables.
#
#   scripts/capture_perf_baseline.sh <fixtures-dir> [<out-basepath>]
#
# <fixtures-dir> must contain small.pdf and large.pdf (see make_perf_fixtures.swift).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Leaf Vocabulary"
APP_BINARY="$ROOT_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <fixtures-dir> [<out-basepath>]" >&2
  exit 2
fi
FIXTURES_DIR="$1"
OUT_BASE="${2:-$ROOT_DIR/docs/perf/baseline}"

if [[ ! -x "$APP_BINARY" ]]; then
  echo "No built app at $APP_BINARY — run scripts/build_app.sh first." >&2
  exit 2
fi
for name in small.pdf large.pdf; do
  if [[ ! -f "$FIXTURES_DIR/$name" ]]; then
    echo "Missing fixture $FIXTURES_DIR/$name — run scripts/make_perf_fixtures.swift." >&2
    exit 2
  fi
done

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
  osascript -e "tell application \"$APP_NAME\" to open POSIX file \"$file\"" >/dev/null 2>&1 || true
  sleep 3
}
open_fixture "$FIXTURES_DIR/small.pdf"
open_fixture "$FIXTURES_DIR/large.pdf"
# Re-open the small one so PDF open has more than a single sample per size.
open_fixture "$FIXTURES_DIR/small.pdf"

echo "==> Quitting (flushes the baseline)"
quit_app
wait "$APP_PID" 2>/dev/null || true
wait_gone

if [[ -f "$OUT_BASE.txt" ]]; then
  echo
  echo "Captured baseline ($OUT_BASE.txt):"
  echo
  cat "$OUT_BASE.txt"
  echo
  echo "JSON written to $OUT_BASE.json"
else
  echo "No baseline written — the app did not flush $OUT_BASE.txt." >&2
  exit 1
fi
