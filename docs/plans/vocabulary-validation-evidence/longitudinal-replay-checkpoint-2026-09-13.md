# Longitudinal replay-coverage checkpoint — 2026-09-13

## Status

The replicated longitudinal development experiment was rerun from clean source
revision `7fbc12a22fd0e9096ecd3221b9c82d4f7a5dbb3b` with schema-2 replay
instrumentation. The already frozen v2 manifest was unchanged. The v2 semantic
report remains retained and was not overwritten.

This is development-only synthetic evidence. It does not bind or execute the
sealed development-confirmation reservation and does not access the release
holdout.

## Non-interference check

All 512 runs and all four original paths (cold/warm natural and cold/warm fixed
budget) match the v2 report exactly for question count, answer-path fingerprint,
posterior fingerprint, selected-deck fingerprint, missed occurrence mass,
realized projected coverage, and conservative coverage lower bound.

The diagnostic extension therefore changed only retained replay evidence. Each
natural and fixed-budget question/evidence path is now reconstructed under both
the cold and accumulated-warm prior, with exact assessable/missed occurrence
mass and realized projected coverage.

## Tail decomposition

The existing two-percentage-point materiality boundary still identifies 13
eligible natural-path failures:

- 11 cease to be material at the common 60-question budget, implicating the
  natural stopping difference under the tested paths.
- `biased-self-verification:learner-22` remains about -14.47 points at fixed
  budget. The same loss appears under either common prior, while changing the
  prior on either fixed evidence path changes realized coverage by 0 points.
  This implicates the changed question/evidence path in this diagnostic case.
- `biased-self-verification:learner-23` remains about -13.84 points at fixed
  budget. Under a common cold prior, the warm question/evidence path is about
  -12.42 points relative to the cold path. Applying the warm prior to the cold
  path is about -13.84 points, while applying it to the warm path is about
  -1.43 points. This is a path-dependent interaction that implicates both
  question/evidence selection and prior sensitivity; it is not a single
  additive effect.

The common-evidence contrasts are conditional decompositions rather than
unique causal effects. They do not justify changing the production warm weight,
disabling personalization, or relaxing an evidence gate.

## Verification and artifacts

- Schema-2 longitudinal validator self-test passed, including negative replay
  mass and evidence-path controls.
- Schema-1 v1 and v2 reports still pass the updated validator.
- Semantic report SHA-256:
  `feebe929620967caa4359b3f0f430399c18d9f3069e5690d61fe892c1337ff49`.
- [Semantic JSON](longitudinal-development-report-v3.json)
- [Concise report](longitudinal-development-report-v3.md)
- [Raw timings](longitudinal-development-timing-v3.json)
- [Tail decomposition](longitudinal-tail-decomposition-v2.md)

## Next action

Predeclare a fresh development experiment for a current-document compatibility
signal before selecting a mitigation. The experiment should retain the existing
paths and adverse cases, define contradiction/support metrics before outcomes,
and compare an 8-question relaxation only when the current document supports
the stored prior. Keep the sealed confirmation reservation and release holdout
untouched until that development decision is frozen.
