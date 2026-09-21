# Longitudinal warm-start simulation checkpoint

Date: 2026-09-08

Base commit: `13f45b318d9b02a2d1ba9492b2c390d9a0923466`

Scope: real-store longitudinal synthetic simulation and direct lifecycle dependencies only.

## Outcome and ownership

The evaluator now has a separate opt-in longitudinal mode that runs coherent multi-document synthetic learners through `VocabularyReaderPriorStore(databaseURL:)` using one disposable SQLite database per learner. The runner loads the production prior before each history assessment, completes the real assessment, records the supplied posterior/count/time/version with a unique contribution ID, reopens the store, verifies idempotency and posterior equivalence, and then forks evaluation document D into uncontaminated cold and accumulated-warm paths.

`scripts/vocabulary_assessment_longitudinal_diagnostics.swift` owns synthetic histories, fixed item effects, learner-item exceptions, addressed potential responses, the fixed clock, disposable stores, natural/fixed/replay comparisons, A/B1/B2 summaries, metrics, and deterministic serialization. It does not import AppKit, use `.shared`, or open `personal-vocabulary.sqlite3`.

`scripts/validate_vocabulary_longitudinal_report.py` independently validates contribution counts, completion/retry/idempotency, reopened posterior identity, production eligibility, cold/warm non-contamination, fixed-budget reachability, exact coverage mass, A parity, B1/B2 deltas, and both replay directions. Negative controls break store counts, eligibility, mass, and replay fingerprints.

`Tests/LeafReaderCoreTests/VocabularyReaderPriorStoreXCTests.swift` adds failed-write/reopen/retry, duplicate contribution, future timestamp, and incompatible-version coverage. `Tests/LeafReaderAppTests/VocabularyPreparationCoordinatorXCTests.swift` proves a failed contribution retries from restored completed state and a stale async completion retries idempotently under the current request. No production coordinator or store code changed.

The evaluator wrapper and self-test now compile/run this opt-in mode under Swift 6 with warnings as errors. Generated wiki navigation was refreshed for the new types.

## Preserved contracts

- The store remains authoritative: it replaces the stored posterior with each supplied completed posterior and increments session/evidence counts. No second accumulation formula was introduced.
- Eligibility remains two completed sessions, 40 verified answers, no future timestamp, age no greater than 180 days, matching language/version, and two current tail validations before the eight-question minimum.
- Only completed assessments call `recordCompletedSession`. A five-answer abandoned history remains incomplete, has no completion time, and contributes nothing.
- Duplicate contribution IDs return success without incrementing counts. Failed writes remain absent and can be retried through a newly opened valid store.
- The same evaluation truth and item-addressed potential-response table is shared by cold, warm, fixed-budget, and replay paths. Changing bank sizes does not change histories, questions, evidence, truth, or potential responses.
- Evaluation completion is not written back, so the cold/warm comparison cannot contaminate its own prior store.
- Natural production stopping is untouched. Fixed-budget continuation uses the explicit diagnostic-only continuation seam, remains bounded by 80/exhaustion, and records bypassed stops/unreachable budgets.
- Common-question/common-evidence replay preserves source order, evidence, and validation metadata in both directions. It is labeled conditional and is not an authentic destination-prior serving path.
- The earlier oracle-informed warm diagnostic is unchanged and remains a separate reference.

## Development manifest and results

The frozen development manifest uses seed `20260909`, one learner in each of 16 scenarios, three 60-lemma history documents (except explicit insufficient/abandoned cases), a 60-question fixed budget, 65% stable overlap or 10% low overlap, fixed item residuals/exceptions, and 4,096-world B1/B2 evaluations.

Scenarios cover stable knowledge, noisy history, biased self-verification, easy→hard and hard→easy histories, changed difficulty distribution, ability drift, low lexical overlap, insufficient history, low verified evidence, stale/future history, incompatible version, reset, failed-write retry, and abandonment.

All 16 runs were retained: 10 were production-eligible and actually used the warm prior; 6 were ineligible and exactly matched cold behavior. The ineligible reasons were one session, zero verified evidence, staleness, future timestamp, algorithm version 2, and reset/no prior.

Among the 10 eligible runs:

- mean natural question reduction was 71.69%, ranging from 46.67% to 81.67%; this tiny development matrix is not a precision-supported estimate;
- mean warm-minus-cold natural realized coverage was -0.1246 percentage points, ranging from -2.0905 to +0.8168 points;
- five scenarios retained adverse natural or fixed-budget coverage movement;
- the largest adverse natural case was `failed-write-retry` at -2.0905 points despite a 73.33% question reduction;
- `changed-difficulty-distribution` had equal natural realized coverage but a -0.7753-point warm-minus-cold difference at the common 60-question budget;
- mean fixed-budget coverage difference was -0.0775 points;
- natural cold/warm question-path Jaccard overlap was low in eligible cases, so natural differences cannot be attributed to the prior alone.

These outcomes do not pass or fail the canonical warm gate: one learner per scenario is insufficient, scenario clustering is not estimated, and no untouched development-confirmation or release holdout was accessed. The adverse and null results remain in the report.

## Reproducibility and production parity

Two identical executions produced byte-identical semantic JSON and Markdown. Changing B1/B2 from 4,096 to 512 worlds preserved every history event, store result, evaluation truth/response fingerprint, natural/fixed path, question/evidence fingerprint, posterior, deck, and replay result outside the bank-specific fields.

The diagnostics-off evaluator remains byte-identical to the pre-slice baseline:

- JSON SHA-256: `0186acd817dfe1602ad80a3953ecd3b69bfb9937f63f9001170d0b108d0e3f77`
- Markdown SHA-256: `c1fced34d26718423ea42f9cdb4b264d67c36fa9d78608e319fcd88239c085a3`
- starting executable SHA-256: `0ede8fdb9c450e9d0d9d956445ebb9248c52272ec31c122fa4fa07c5c0bf14af`

The final report records source revision `13f45b3`, dirty source-status fingerprint `6d157d2cbe76f3bd`, and dirty source-content fingerprint `ae61d0597aa6f3c25f8be2c793ef6447d51c9c4e7a7fc969a60c958a24f682ab`.

## Timing

Raw current-host phase observations are stored separately from deterministic semantics:

| Phase | Repetitions | Mean ms | Range ms |
| --- | ---: | ---: | ---: |
| History assessment | 47 | 25.631 | 3.147–96.662 |
| Reopened store round trip | 47 | 5.998 | 3.692–23.451 |
| Four evaluation paths | 16 | 172.705 | 73.473–560.166 |
| Bidirectional replay | 16 | 10.783 | 3.457–29.904 |
| Semantic serialization | 3 | 14.864 | 12.069–17.385 |

The final paired diagnostics-off whole-process benchmark retained nine alternating repetitions. Means were 383.212 ms baseline and 382.421 ms candidate, a -0.791 ms (-0.21%) delta with exact output parity. Host-load variation is substantial, so this indicates no material detected overhead rather than an improvement. Longitudinal work is not mixed into the product 150 ms gate.

## Verification

- `swift test --filter VocabularyReaderPriorStoreXCTests` — 6 tests, 0 failures.
- `swift test --filter VocabularyPreparationCoordinatorXCTests` — 15 tests, 0 failures.
- `./scripts/test_vocabulary_assessment_evaluator.sh` — standard, causal, and longitudinal deterministic/self-test/validator checks passed.
- Same-manifest semantic `cmp`, changed-bank coupling comparison, and diagnostics-off baseline `cmp` passed.
- `python3 scripts/validate_vocabulary_longitudinal_report.py ... --self-test` passed the report plus four negative controls.
- `./scripts/check.sh --no-build` passed on the final tree: Core portability/ownership, native-reader boundary, strict Swift 6 build, 158 Swift tests with one expected private-fixture skip, 281 logic tests, and all deterministic validators.

`./scripts/build_app.sh` was not run because no app assembly, resources, framework linkage, UI, or native-reader behavior changed. The strict package build compiled the app target.

## Artifacts

- [Frozen longitudinal manifest](longitudinal-development-manifest-v1.json) — SHA-256 `d786833bd22ade6716668676b212e48cbb3542781eb812d652bd2e47d0cf803a`
- [Machine-readable longitudinal report](longitudinal-development-report-v1.json) — SHA-256 `53eff35085229369ebc9221d6f22c2d083526824a641dc6c889fc4090d2d253f`
- [Concise longitudinal report](longitudinal-development-report-v1.md) — SHA-256 `08061111b9413966adaa78a1a499dd16b5bac980b50fded125260497d4d60242`
- [Raw longitudinal timing](longitudinal-development-timing-v1.json) — SHA-256 `77cc0b26748c44e1232091ba5ab4bf8fb6604b06c00ca4cd6f013d29721a7434`
- [Diagnostics-off overhead](longitudinal-diagnostics-off-overhead-v1.json) — SHA-256 `73493235a1e04b7af82b3f98260312ef94478a7e623618787439084dc0433488`

## Recommendation and stop boundary

The real-store longitudinal infrastructure is ready for a larger, precision-planned diagnostic-development matrix and, after candidate/analysis freeze, a separately reserved development-confirmation set. The present outcomes are not strong enough to claim warm non-inferiority: the adverse natural and fixed-budget cells require continued development analysis, not gate relaxation.

The next planned implementation slice is the entirely fabricated study-package/analysis rehearsal. It may proceed without participant data, but canonical study amendments, confirmatory collection, calibration activation, POS policy changes, and release-holdout access remain outside this checkpoint.
