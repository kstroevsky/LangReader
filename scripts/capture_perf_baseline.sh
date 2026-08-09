#!/usr/bin/env bash
# Captures a performance baseline by driving the real app.
#
# The app records nothing unless LEAFVOCAB_PERF=1. This runner records cold and
# warm process phases separately, with a fresh fixture path for each pair so a
# prior user session cannot silently turn the cold phase into a cache hit.
#
# Synthetic mode captures launch, main window, PDF open, first-page display,
# and theme apply. Private mode validates representative PDF/EPUB/DOCX fixtures,
# opens all of them, pauses for the database-backed and AI surfaces, and writes
# a path-free metadata sidecar next to the aggregate report.
#
#   scripts/capture_perf_baseline.sh <fixtures-dir> [<out-basepath>]
#   scripts/capture_perf_baseline.sh --document-fixtures <pdf> <epub> <docx> [<out-basepath>]
#   scripts/capture_perf_baseline.sh --matrix-fixtures <clean-pdf> <complex-pdf> <ocr-pdf> <normal-epub> <large-epub> [<out-basepath>]
#   scripts/capture_perf_baseline.sh --interaction-fixtures <pdf> <epub> [<out-basepath>]
#   scripts/capture_perf_baseline.sh --private-manifest <manifest.json> [<out-basepath>]
#
# <fixtures-dir> must contain small.pdf and large.pdf (see make_perf_fixtures.swift).
# The private manifest must remain uncommitted; copy docs/perf/private-fixtures.example.json.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Leaf Vocabulary"
APP_BINARY="$ROOT_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"
MANIFEST_TOOL="$ROOT_DIR/scripts/private_perf_fixture_manifest.swift"
VALIDATOR="$ROOT_DIR/scripts/validate_perf_capture.swift"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/private/tmp/leafreader-clang-cache}"

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <fixtures-dir> [<out-basepath>]" >&2
  echo "       $0 --document-fixtures <pdf> <epub> <docx> [<out-basepath>]" >&2
  echo "       $0 --matrix-fixtures <clean-pdf> <complex-pdf> <ocr-pdf> <normal-epub> <large-epub> [<out-basepath>]" >&2
  echo "       $0 --interaction-fixtures <pdf> <epub> [<out-basepath>]" >&2
  echo "       $0 --private-manifest <manifest.json> [<out-basepath>]" >&2
  exit 2
fi

PRIVATE_MODE=0
DOCUMENT_MODE=0
MATRIX_MODE=0
INTERACTION_MODE=0
FIXTURE_FILES=()
PRIVATE_MANIFEST=""
if [[ "$1" == "--interaction-fixtures" ]]; then
  if [[ $# -lt 3 || ! -f "$2" || "${2##*.}" != "pdf" || ! -f "$3" || "${3##*.}" != "epub" ]]; then
    echo "--interaction-fixtures requires readable PDF and EPUB paths" >&2
    exit 2
  fi
  INTERACTION_MODE=1
  FIXTURE_FILES=("$2" "$3")
  OUT_BASE="${4:-/tmp/leafreader-interaction-performance}"
elif [[ "$1" == "--matrix-fixtures" ]]; then
  if [[ $# -lt 6 ]]; then
    echo "--matrix-fixtures requires three PDF and two EPUB paths" >&2
    exit 2
  fi
  MATRIX_MODE=1
  FIXTURE_FILES=("$2" "$3" "$4" "$5" "$6")
  EXPECTED_EXTENSIONS=(pdf pdf pdf epub epub)
  for index in 0 1 2 3 4; do
    fixture="${FIXTURE_FILES[$index]}"
    expected_extension="${EXPECTED_EXTENSIONS[$index]}"
    if [[ ! -f "$fixture" || "${fixture##*.}" != "$expected_extension" ]]; then
      echo "Matrix fixture $fixture must be a readable .$expected_extension file" >&2
      exit 2
    fi
  done
  OUT_BASE="${7:-/tmp/leafreader-performance-matrix}"
elif [[ "$1" == "--document-fixtures" ]]; then
  if [[ $# -lt 4 ]]; then
    echo "--document-fixtures requires PDF, EPUB, and DOCX paths" >&2
    exit 2
  fi
  DOCUMENT_MODE=1
  FIXTURE_FILES=("$2" "$3" "$4")
  EXPECTED_EXTENSIONS=(pdf epub docx)
  for index in 0 1 2; do
    fixture="${FIXTURE_FILES[$index]}"
    expected_extension="${EXPECTED_EXTENSIONS[$index]}"
    if [[ ! -f "$fixture" || "${fixture##*.}" != "$expected_extension" ]]; then
      echo "Document fixture $fixture must be a readable .$expected_extension file" >&2
      exit 2
    fi
  done
  OUT_BASE="${5:-/tmp/leafreader-document-baseline}"
elif [[ "$1" == "--private-manifest" ]]; then
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
OUT_DIRECTORY="$(cd "$(dirname "$OUT_BASE")" && pwd)"
OUT_BASE="$OUT_DIRECTORY/$(basename "$OUT_BASE")"
RUN_DIRECTORY="$(mktemp -d "$(dirname "$OUT_BASE")/.perf-capture.XXXXXX")"
RUN_STARTED="$(date +%s)"
PERFORMANCE_ENVIRONMENT_INSTALLED=0
SOURCE_REVISION="$(git -C "$ROOT_DIR" rev-parse HEAD)"
if ! git -C "$ROOT_DIR" diff --quiet HEAD -- Sources Package.swift scripts/build_app.sh \
  || [[ -n "$(git -C "$ROOT_DIR" ls-files --others --exclude-standard -- Sources Package.swift scripts/build_app.sh)" ]]; then
  SOURCE_REVISION="$SOURCE_REVISION+dirty"
fi
BUILD_SHA256="$(shasum -a 256 "$APP_BINARY" | awk '{print $1}')"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"

# Copies isolate the cold phase from existing document/session caches while the
# warm phase intentionally reopens the exact same paths.
CAPTURE_FIXTURES=()
fixture_index=0
for fixture in "${FIXTURE_FILES[@]}"; do
  extension="${fixture##*.}"
  copied_fixture="$RUN_DIRECTORY/fixture-$fixture_index.$extension"
  cp -p "$fixture" "$copied_fixture"
  CAPTURE_FIXTURES+=("$copied_fixture")
  fixture_index=$((fixture_index + 1))
done
FIXTURE_SET="$(for fixture in "${CAPTURE_FIXTURES[@]}"; do shasum -a 256 "$fixture"; done | awk '{print $1}' | shasum -a 256 | awk '{print $1}')"

quit_app() { osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true; }
app_is_running() { pgrep -x "$APP_NAME" >/dev/null; }
wait_gone() {
  for _ in $(seq 1 50); do pgrep -x "$APP_NAME" >/dev/null || return 0; sleep 0.2; done
}
clear_performance_environment() {
  if [[ "$PERFORMANCE_ENVIRONMENT_INSTALLED" == "1" ]]; then
    launchctl unsetenv LEAFVOCAB_PERF || true
    launchctl unsetenv LEAFVOCAB_PERF_OUT || true
    launchctl unsetenv LEAFVOCAB_PERF_PHASE || true
    launchctl unsetenv LEAFVOCAB_PERF_CONFIGURATION || true
    launchctl unsetenv LEAFVOCAB_PERF_SOURCE_REVISION || true
    launchctl unsetenv LEAFVOCAB_PERF_BUILD_SHA256 || true
    launchctl unsetenv LEAFVOCAB_PERF_FIXTURE_SET || true
    launchctl unsetenv LEAFVOCAB_PERF_RUN_ID || true
    launchctl unsetenv LEAFVOCAB_PERF_DISABLE_SESSION_RESTORE || true
    launchctl unsetenv LEAFVOCAB_PERF_AUTOMATION || true
  fi
}
trap clear_performance_environment EXIT

open_fixture() {
  local file="$1"
  echo "==> Opening $(basename "$file")"
  /usr/bin/open -a "$ROOT_DIR/$APP_NAME.app" "$file"
  if [[ "$INTERACTION_MODE" == "1" ]]; then
    sleep "${LEAFREADER_PERF_INTERACTION_WAIT:-30}"
  elif [[ "$DOCUMENT_MODE" == "1" || "$MATRIX_MODE" == "1" ]]; then
    sleep "${LEAFREADER_PERF_OPEN_WAIT:-8}"
  else
    sleep 3
  fi
  if ! app_is_running; then
    echo "Performance capture app exited while opening $file." >&2
    exit 1
  fi
}

run_phase() {
  local phase="$1"
  local run_base="$RUN_DIRECTORY/$phase"
  local phase_started
  phase_started="$(date +%s)"

  echo "==> Starting $phase process phase"
  quit_app
  wait_gone
  launchctl setenv LEAFVOCAB_PERF 1
  launchctl setenv LEAFVOCAB_PERF_OUT "$run_base"
  launchctl setenv LEAFVOCAB_PERF_PHASE "$phase"
  launchctl setenv LEAFVOCAB_PERF_CONFIGURATION release
  launchctl setenv LEAFVOCAB_PERF_SOURCE_REVISION "$SOURCE_REVISION"
  launchctl setenv LEAFVOCAB_PERF_BUILD_SHA256 "$BUILD_SHA256"
  launchctl setenv LEAFVOCAB_PERF_FIXTURE_SET "$FIXTURE_SET"
  launchctl setenv LEAFVOCAB_PERF_RUN_ID "$RUN_ID-$phase"
  launchctl setenv LEAFVOCAB_PERF_DISABLE_SESSION_RESTORE 1
  if [[ "$INTERACTION_MODE" == "1" ]]; then
    launchctl setenv LEAFVOCAB_PERF_AUTOMATION 1
  fi
  PERFORMANCE_ENVIRONMENT_INSTALLED=1

  open -n "$ROOT_DIR/$APP_NAME.app"
  for _ in $(seq 1 40); do
    app_is_running && break
    sleep 0.25
  done
  sleep 2
  if ! app_is_running; then
    echo "Performance capture app exited during $phase launch." >&2
    exit 1
  fi

  for fixture in "${CAPTURE_FIXTURES[@]}"; do
    open_fixture "$fixture"
  done

  if [[ "$PRIVATE_MODE" == "1" && "$phase" == "warm" ]]; then
    private_checkpoint
  fi

  echo "==> Quitting $phase phase (flushes raw samples)"
  quit_app
  wait_gone
  if [[ ! -f "$run_base.txt" || ! -f "$run_base.json" ]]; then
    echo "No $phase baseline written — the app did not flush $run_base.txt." >&2
    exit 1
  fi

  if [[ "$INTERACTION_MODE" == "1" ]]; then
    swift "$VALIDATOR" interactions "$run_base.json" --not-before "$phase_started" --expected-phase "$phase"
  elif [[ "$PRIVATE_MODE" == "1" && "$phase" == "warm" ]]; then
    swift "$VALIDATOR" private "$run_base.json" --not-before "$phase_started" --expected-phase "$phase"
  elif [[ "$PRIVATE_MODE" == "1" ]]; then
    swift "$VALIDATOR" documents "$run_base.json" --not-before "$phase_started" --expected-phase "$phase"
  elif [[ "$MATRIX_MODE" == "1" ]]; then
    swift "$VALIDATOR" matrix "$run_base.json" --not-before "$phase_started" --expected-phase "$phase"
  elif [[ "$DOCUMENT_MODE" == "1" ]]; then
    swift "$VALIDATOR" documents "$run_base.json" --not-before "$phase_started" --expected-phase "$phase"
  else
    swift "$VALIDATOR" synthetic "$run_base.json" --not-before "$phase_started" --expected-phase "$phase"
  fi
}

private_checkpoint() {
  if [[ ! -t 0 ]]; then
    echo "Private capture needs an interactive terminal for its manual surface checkpoint." >&2
    echo "Open Shelf, Notes, Vocabulary Library, a long AI conversation, and selection tools, then run this command in Terminal." >&2
    exit 2
  fi
  echo
  echo "==> Exercise the representative data surfaces now"
  echo "    Open Shelf, Notes, Vocabulary Library, a long AI conversation,"
  echo "    selection tools, and switch theme. Press Return when complete."
  read -r
}

echo "==> Stopping any running instance"
quit_app
wait_gone
if [[ "$INTERACTION_MODE" == "1" ]]; then
  run_phase interaction
else
  run_phase cold
  run_phase warm
fi

if [[ "$INTERACTION_MODE" == "1" ]]; then
  mv "$RUN_DIRECTORY/interaction.txt" "$OUT_BASE.interaction.txt"
  mv "$RUN_DIRECTORY/interaction.json" "$OUT_BASE.interaction.json"
else
  mv "$RUN_DIRECTORY/cold.txt" "$OUT_BASE.cold.txt"
  mv "$RUN_DIRECTORY/cold.json" "$OUT_BASE.cold.json"
  mv "$RUN_DIRECTORY/warm.txt" "$OUT_BASE.warm.txt"
  mv "$RUN_DIRECTORY/warm.json" "$OUT_BASE.warm.json"
fi
if [[ "$PRIVATE_MODE" == "1" ]]; then
  swift "$MANIFEST_TOOL" metadata "$PRIVATE_MANIFEST" "$OUT_BASE.fixtures.json"
fi
rm -f "${CAPTURE_FIXTURES[@]}"
rmdir "$RUN_DIRECTORY"

echo
if [[ "$INTERACTION_MODE" == "1" ]]; then
  echo "Captured interaction baseline ($OUT_BASE.interaction.txt):"
  cat "$OUT_BASE.interaction.txt"
  echo "Raw-sample JSON written to $OUT_BASE.interaction.json"
else
  echo "Captured cold baseline ($OUT_BASE.cold.txt):"
  cat "$OUT_BASE.cold.txt"
  echo
  echo "Captured warm baseline ($OUT_BASE.warm.txt):"
  cat "$OUT_BASE.warm.txt"
  echo
  echo "Raw-sample JSON written to $OUT_BASE.cold.json and $OUT_BASE.warm.json"
fi
if [[ "$PRIVATE_MODE" == "1" ]]; then
  echo "Path-free fixture metadata written to $OUT_BASE.fixtures.json"
fi
