#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
allowlist="$root/scripts/reader_native_access_allowlist.txt"
actual="$(mktemp)"
trap 'rm -f "$actual"' EXIT

cd "$root"
if [[ ! -f "$allowlist" ]]; then
  echo "Reader native-access allowlist is missing: $allowlist" >&2
  exit 1
fi
if ! LC_ALL=C sort -cu "$allowlist"; then
  echo "Reader native-access allowlist must be sorted and contain no duplicates." >&2
  exit 1
fi

rg -l '\b(pdfView|webView)\b' Sources/LeafReaderApp --glob '*.swift' | sort > "$actual"
unexpected="$(comm -23 "$actual" "$allowlist")"
stale="$(comm -13 "$actual" "$allowlist")"
if [[ -n "$unexpected" ]]; then
  echo "Direct PDFView/WKWebView access outside the reviewed platform-coordination allowlist:" >&2
  echo "$unexpected" >&2
  echo "Extend an adapter or add a narrow platform service; do not allowlist a file merely to pass this check." >&2
  exit 1
fi
if [[ -n "$stale" ]]; then
  echo "Stale Reader native-access allowlist entries (remove them so the debt moves downward):" >&2
  echo "$stale" >&2
  exit 1
fi

echo "Reader native-view access seam: ok ($(wc -l < "$actual" | tr -d ' ') allowlisted files)"
