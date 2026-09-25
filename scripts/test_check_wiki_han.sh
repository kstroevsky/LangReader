#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCANNER="$ROOT_DIR/scripts/check_wiki_han.pl"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leafreader-wiki-han.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

SAFE_FILE="$TEMP_DIR/safe.md"
HAN_FILE="$TEMP_DIR/han.md"
MALFORMED_FILE="$TEMP_DIR/malformed.md"

printf 'R(S) = (1 - q) · C_FS\n' > "$SAFE_FILE"
printf 'Contains Han: 中\n' > "$HAN_FILE"
python3 - "$MALFORMED_FILE" <<'PY'
from pathlib import Path
import sys

Path(sys.argv[1]).write_bytes(b"malformed: \xff\n")
PY

"$SCANNER" "$SAFE_FILE"

status=0
output="$("$SCANNER" "$HAN_FILE" 2>&1)" || status=$?
if [[ "$status" -ne 10 || "$output" != *"U+4E2D"* ]]; then
  echo "FAIL wiki Han scanner: Han text was not reported with exit 10: $output" >&2
  exit 1
fi

status=0
output="$("$SCANNER" "$MALFORMED_FILE" 2>&1)" || status=$?
if [[ "$status" -ne 20 || "$output" != *"UTF-8 decode error"* ]]; then
  echo "FAIL wiki Han scanner: malformed UTF-8 did not use the scanner-error path: $output" >&2
  exit 1
fi

echo "wiki Han-script scanner tests passed"
