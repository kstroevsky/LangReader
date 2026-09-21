# Usable-question latency checkpoint — 2026-09-09

## Status

The opt-in instrumentation and deterministic capture contract are implemented.
The private cross-format GUI capture is awaiting its external fixture manifest,
so this checkpoint does not claim real-app latency values or acceptance.

## Implemented measurement boundary

Four monotonic interaction spans extend the existing `ReaderPerformance` and
`PerformanceEvent` pipeline:

- answer submission to learning content presented;
- Continue to the next word presented;
- Continue to the next word's answer controls enabled;
- known-answer verification to the next word's answer controls enabled.

The coordinator starts spans and validates the current candidate and assessment
state. SwiftUI presentation callbacks finish the visible and answerable spans;
the answerable endpoint additionally requires enabled controls, so deferred
coverage work can finish after word visibility without collapsing the two
measurements. Existing request/document guards continue to reject stale async
callbacks.

Completed durations use the existing deterministic performance report. Failed
definition lookup, terminal results, cancellation, reset, document replacement,
and window teardown close outstanding spans with explicit outcome-only local
log records. They do not become zero-duration successes. The feature is a no-op
unless `LEAFVOCAB_PERF=1`; the disabled-path test proves it does not read the
clock or emit an observation.

The performance automation now exercises known verification and
unknown/learning/Continue paths rather than the obsolete reveal-then-score
sequence. The `vocabulary-preparation` validator requires every completed span
to be present. No new latency threshold was introduced: these spans remain
diagnostic and do not weaken the existing 150 ms algorithm, 16 ms main-thread,
or document-open control gates.

## Deterministic evidence

- `VocabularyPreparationInteractionTimingXCTests`: two tests passed, covering
  exact monotonic durations, word-visible-before-answerable ordering, duplicate
  starts, failed/terminal/cancelled closure, and the disabled path.
- `VocabularyPreparationCoordinatorXCTests`: all 15 tests passed, including
  retained exact/precomputed known behavior, deferred work, retry/skip, stale
  completion rejection, PDF/Web inventory parity, persistence, and import.
- `scripts/test_perf_capture_validator.sh`: passed, including the positive
  preparation fixture and a negative fixture missing the new interaction event.
- `./scripts/build_app.sh`: passed and produced a signed app. Optional local TTS
  runtimes/voices were absent and reported by the existing build warnings; this
  does not affect vocabulary preparation.

- `./scripts/check.sh --no-build`: passed after the generated wiki was refreshed;
  this included 165 Swift tests (one intentional skip), the regression harness,
  281 logic tests, capture-validator fixtures, assessment/calibration/study/POS
  evaluators, domain-resource builders, and benchmark/stopping self-tests.

## GUI capture prerequisite

macOS Accessibility permission is enabled on this host. Only the committed
example manifests are present; no private English/German PDF/EPUB/DOCX manifest
or its six documents are available. Therefore the required real GUI matrix,
instrumented/uninstrumented overhead comparison, raw interaction samples, and
p50/p95/p99/max/missing/cancelled summaries have not been run. This is an
environment/fixture prerequisite, not a passing measurement or a product
failure.

## Next action

Create the reproducible redistributable English/German PDF/EPUB/DOCX supplement,
then run the private six-document matrix when its manifest is supplied. Preserve
all repetitions and unfavorable outcomes before freezing any diagnostic
interaction thresholds.
