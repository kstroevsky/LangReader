#!/usr/bin/env bash
# Captures a low-overhead process resource series plus an Instruments trace for
# an already-running performance session.
set -euo pipefail

APP_NAME="${LEAFVOCAB_PROFILE_APP_NAME:-Leaf Vocabulary}"
DURATION_SECONDS="${1:-30}"
OUT_DIR="${2:-/tmp/leafreader-performance-profile}"
TEMPLATE="${3:-Time Profiler}"

if ! [[ "$DURATION_SECONDS" =~ ^[0-9]+$ ]] || (( DURATION_SECONDS < 1 )); then
  echo "usage: $0 <duration-seconds> [out-dir] [xctrace-template]" >&2
  exit 2
fi
PID="$(pgrep -x "$APP_NAME" | head -1)"
if [[ -z "$PID" ]]; then
  echo "$APP_NAME is not running" >&2
  exit 2
fi
mkdir -p "$OUT_DIR"
TRACE_SLUG="$(tr '[:upper:] ' '[:lower:]-' <<<"$TEMPLATE")"
TRACE_PATH="$OUT_DIR/$TRACE_SLUG.trace"
RESOURCE_PATH="$OUT_DIR/process-resources.csv"
rm -rf "$TRACE_PATH"

echo "sample,epoch_seconds,rss_kb,cpu_percent,cpu_time" > "$RESOURCE_PATH"
(
  sample_index=0
  while kill -0 "$PID" 2>/dev/null; do
    row="$(ps -p "$PID" -o rss=,%cpu=,time= | awk '{$1=$1; print}')"
    [[ -n "$row" ]] || break
    epoch="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"
    read -r rss cpu cpu_time <<<"$row"
    echo "$sample_index,$epoch,$rss,$cpu,$cpu_time" >> "$RESOURCE_PATH"
    sample_index=$((sample_index + 1))
    sleep 0.1
  done
) &
SAMPLER_PID=$!

cleanup() {
  kill "$SAMPLER_PID" >/dev/null 2>&1 || true
  wait "$SAMPLER_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

xcrun xctrace record \
  --template "$TEMPLATE" \
  --attach "$PID" \
  --time-limit "${DURATION_SECONDS}s" \
  --output "$TRACE_PATH"

cleanup
trap - EXIT
xcrun xctrace export --input "$TRACE_PATH" --toc --output "$OUT_DIR/$TRACE_SLUG-toc.xml"

awk -F, 'NR > 1 { if ($3 > peak) peak=$3; cpu+=$4; n++ } END { printf "samples=%d peak_rss_kb=%.0f mean_cpu_percent=%.2f\n", n, peak, n ? cpu/n : 0 }' "$RESOURCE_PATH"
echo "Trace: $TRACE_PATH"
echo "Resources: $RESOURCE_PATH"
