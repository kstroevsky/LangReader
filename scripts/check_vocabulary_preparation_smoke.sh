#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${LEAFVOCAB_UI_SMOKE:-0}" != "1" ]]; then
  echo "Set LEAFVOCAB_UI_SMOKE=1 to run the six-document GUI preparation smoke." >&2
  exit 3
fi
if [[ $# -ne 1 ]]; then
  echo "usage: $0 <private-six-fixture-manifest.json>" >&2
  exit 2
fi
if ! osascript -e 'tell application "System Events" to get UI elements enabled' 2>/dev/null | grep -q true; then
  echo "Accessibility permission is required for GUI smoke testing." >&2
  exit 3
fi
"$ROOT_DIR/scripts/capture_perf_baseline.sh" \
  --vocabulary-preparation-manifest "$1" \
  "${LEAFREADER_VOCABULARY_SMOKE_OUT:-/tmp/leafreader-vocabulary-preparation-smoke}"
