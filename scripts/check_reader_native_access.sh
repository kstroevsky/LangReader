#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
allowlist="$root/scripts/reader_native_access_allowlist.txt"
actual="$(mktemp)"
trap 'rm -f "$actual"' EXIT

cd "$root"
rg -l '\b(pdfView|webView)\b' Sources/LeafReaderApp --glob '*.swift' | sort > "$actual"
unexpected="$(comm -23 "$actual" "$allowlist")"
if [[ -n "$unexpected" ]]; then
  echo "Direct PDFView/WKWebView access outside the reviewed platform-coordination allowlist:" >&2
  echo "$unexpected" >&2
  exit 1
fi
