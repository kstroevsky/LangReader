#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
validator="$root/scripts/validate_perf_capture.swift"
fixtures="$root/scripts/perf_validator_fixtures"

swift "$validator" synthetic "$fixtures/valid-synthetic.json"
swift "$validator" synthetic "$fixtures/valid-synthetic.json" --expected-phase cold
swift "$validator" documents "$fixtures/valid-documents.json"
swift "$validator" docx "$fixtures/valid-docx-cold.json" --expected-phase cold
swift "$validator" docx "$fixtures/valid-docx-warm.json" --expected-phase warm
swift "$validator" matrix "$fixtures/valid-matrix.json"
swift "$validator" interactions "$fixtures/valid-interactions.json"
for fixture in invalid.json missing-event.json undersampled.json invalid-raw-samples.json missing-visible-ready.json; do
  if swift "$validator" synthetic "$fixtures/$fixture"; then
    echo "validator unexpectedly accepted $fixture" >&2
    exit 1
  fi
done
if swift "$validator" interactions "$fixtures/interaction-threshold-regression.json"; then
  echo "validator unexpectedly accepted an interaction threshold regression" >&2
  exit 1
fi
if swift "$validator" interactions "$fixtures/scroll-degradation-regression.json"; then
  echo "validator unexpectedly accepted background-index scroll degradation" >&2
  exit 1
fi
if swift "$validator" synthetic "$fixtures/valid-synthetic.json" --expected-phase warm; then
  echo "validator unexpectedly accepted the wrong capture phase" >&2
  exit 1
fi
if swift "$validator" docx "$fixtures/valid-docx-warm.json" --expected-phase cold; then
  echo "validator unexpectedly accepted warm DOCX stages as cold" >&2
  exit 1
fi
if swift "$validator" synthetic "$fixtures/valid-synthetic.json" --not-before "$(($(date +%s) + 60))"; then
  echo "validator unexpectedly accepted a stale report" >&2
  exit 1
fi
