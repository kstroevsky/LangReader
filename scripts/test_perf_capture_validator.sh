#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
validator="$root/scripts/validate_perf_capture.swift"
fixtures="$root/scripts/perf_validator_fixtures"

swift "$validator" synthetic "$fixtures/valid-synthetic.json"
for fixture in invalid.json missing-event.json undersampled.json; do
  if swift "$validator" synthetic "$fixtures/$fixture"; then
    echo "validator unexpectedly accepted $fixture" >&2
    exit 1
  fi
done
if swift "$validator" synthetic "$fixtures/valid-synthetic.json" --not-before "$(($(date +%s) + 60))"; then
  echo "validator unexpectedly accepted a stale report" >&2
  exit 1
fi
