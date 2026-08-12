#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
capture="$root/scripts/capture_perf_baseline.sh"
summary="$root/scripts/summarize_docx_performance.swift"
app_binary="$root/Leaf Vocabulary.app/Contents/MacOS/Leaf Vocabulary"

if [[ $# -lt 4 || $# -gt 5 ]]; then
  echo "usage: $0 <pdf> <epub> <docx> <output-directory> [pairs]" >&2
  exit 2
fi

pdf="$1"
epub="$2"
docx="$3"
output_directory="$4"
pairs="${5:-5}"
if [[ ! -f "$pdf" || ! -f "$epub" || ! -f "$docx" || ! "$pairs" =~ ^[1-9][0-9]*$ ]]; then
  echo "fixtures must be readable and pairs must be a positive integer" >&2
  exit 2
fi
if [[ ! -x "$app_binary" ]]; then
  echo "build the Release app before capturing DOCX performance" >&2
  exit 2
fi

mkdir -p "$output_directory"
initial_sha="$(shasum -a 256 "$app_binary" | awk '{print $1}')"
reports=()
for pair in $(seq 1 "$pairs"); do
  base="$output_directory/pair-$pair"
  echo "==> DOCX performance pair $pair/$pairs"
  "$capture" --document-fixtures "$pdf" "$epub" "$docx" "$base"
  reports+=("$base.cold.json" "$base.warm.json")
done
final_sha="$(shasum -a 256 "$app_binary" | awk '{print $1}')"
if [[ "$initial_sha" != "$final_sha" ]]; then
  echo "Release binary changed during DOCX benchmark" >&2
  exit 1
fi

swift "$summary" "${reports[@]}"
