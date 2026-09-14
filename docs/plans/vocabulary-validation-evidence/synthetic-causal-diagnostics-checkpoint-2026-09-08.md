# Synthetic causal diagnostics checkpoint

Date: 2026-09-08  
Execution boundary: first milestone only; longitudinal warm simulation and all later plan slices remain unimplemented.

## Outcome

The repository now has an explicit opt-in synthetic causal-diagnostics path that freezes an assessment/deck, evaluates production bank A and independent B1/B2 banks, conserves missed occurrence mass exactly, retains all development runs, supports bounded fixed-budget continuation and both common-evidence replay directions, validates its own artifact, and reports diagnostic cost separately from product latency.

No production selector, production sample count, stopping rule, model dimension, study schema, persistence schema, native-reader boundary, release gate, frozen holdout, or version-2 golden changed. No participant data, private document, live GUI, user database, confirmation set, or release holdout was accessed.

## Ownership and changed files

- `Sources/LeafReaderCore/VocabularyReview/VocabularyAssessmentCausalDiagnostics.swift` owns the immutable assessment snapshot, fixed-bank evaluator, A/B1/B2 sampling semantics, exact quantile/miss calculation, bank fingerprints, input rejection, and fixed-deck controls. It calls the existing `VocabularyKnowledgeModel` and `VocabularyObservationModel`; it does not copy the likelihood into an offline language.
- `Sources/LeafReaderCore/VocabularyReview/AdaptiveVocabularyAssessment.swift` exposes the read-only snapshot and a narrowly named diagnostic continuation entry point. Normal `nextQuestion()` still follows the unchanged production stop; the diagnostic method is usable only through an explicit call and still enforces the 80-answer ceiling, exhaustion, exclusions, skips, and duplicate-answer protection.
- `scripts/vocabulary_assessment_causal_diagnostics.swift` owns synthetic documents, actual-difficulty provenance, addressed truth and potential-response tables, natural/fixed/replay orchestration, forensic rows, run/source fingerprints, semantic serialization, and phase timings.
- `scripts/evaluate_vocabulary_assessment.swift` and `scripts/evaluate_vocabulary_assessment.sh` add opt-in causal flags and compile the evaluator in Swift 6 with warnings as errors. The default evaluator schema and random stream remain unchanged.
- `scripts/validate_vocabulary_causal_diagnostic_report.py` validates run joins, uniqueness, exact mass conservation, reachability, A/B shapes, B1 theta mass, fingerprints, and natural/fixed coupling. Negative controls cover broken denominators, duplicate runs, missing fingerprints, and corrupted B1 mass.
- `scripts/measure_vocabulary_evaluator_diagnostics_off.py` measures the unchanged path against the captured starting executable with paired alternating process runs.
- `Tests/LeafReaderCoreTests/VocabularyAssessmentCausalDiagnosticsXCTests.swift` contains the independent four-world oracle, A mask/quantile parity, biased-bank fixed-deck control, RNG isolation, zero-mass inverse-CDF, nonmutation, continuation, replay, and invalid-input tests.
- `scripts/fixtures/vocabulary-causal-diagnostic-manifest-v1.json` is the inexpensive evaluator-test manifest; its unreachable 80-question budget on 20 items proves exhaustion is recorded rather than filled with duplicate answers.
- `scripts/test_vocabulary_assessment_evaluator.sh` now includes causal self-test, deterministic rerun, artifact validation, and validator negative controls.
- `docs/wiki/code-map.md` and `docs/wiki/type-index.md` were regenerated because the repository check requires generated navigation to include the new types.
- `docs/plans/vocabulary-validation-evidence/diagnostic-development-manifest-v1.json` freezes the development run before outcomes: seed 20260908, two readers, two documents, 60 lemmas, four scenarios, 60-question fixed budget, three replicas, A=512, B1/B2=512 and 4,096, fixed five-item frequency deck, retain-all policy, and within-stratum B2 jitter.

## Mathematical and statistical invariants

- Bank A is the exact production 512-world mask bank and midpoint theta strata used to construct and report the frozen deck. Its diagnostic fifth percentile is bit/mask-derived and equals the production result exactly.
- B1 repeats each of A's 512 theta positions evenly, so the posterior-position mass is identical. Only its latent-item draws are independently seeded. Unsupported sample counts that cannot preserve all 512 positions are rejected.
- B2 uses independent uniform jitter within each of `N` equal posterior-mass strata, a separate theta-position seed, and a separate latent-item seed. Its inverse CDF skips zero-mass cells and assigns half-open boundaries deterministically.
- Every bank evaluates the same frozen selected set and assessable denominator for its deck role. The report retains both the production-selected deck and a five-item frequency-fixed deck independent of A.
- The fifth percentile uses index `floor(q × (N - 1))`, matching production. Target-miss probability is the empirical fraction of bank worlds below 0.98.
- For included items, `W`, `missedMass`, projected coverage, and shortfall are calculated from integers before conversion. `answeredMissedMass + unaskedMissedMass == missedMass`, and answered evidence-category mass equals answered missed mass. Skipped mass is a named subset of unasked mass. Excluded mass never enters `W`.
- Empty denominators produce coverage 1, shortfall 0, and `claimEligible=false`. Invalid weights, duplicate keys, missing truth, non-finite probabilities, malformed masks/posteriors, excluded/unknown selection keys, incompatible snapshot identity, and invalid bank shapes fail explicitly.
- Flip, response mismatch/uncertainty, and effective difficulty residual remain overlapping provenance flags; the report does not present them as an additive causal decomposition.

## Production parity and reproducibility

Starting revision: `e8ea803c2a9eb557677a520f4c97aacf729e7c52`. The final semantic report records a dirty source-content fingerprint of `a13b6c3453858a3a92b8b73f46c69d4f8afb4a6e3c58a29958b8201eab659f29`; it does not pretend the tree is clean.

The starting seed-42, 2-reader, 2-document, 60-lemma artifacts and captured executable were recreated before source edits:

- baseline JSON SHA-256: `0186acd817dfe1602ad80a3953ecd3b69bfb9937f63f9001170d0b108d0e3f77`
- baseline Markdown SHA-256: `c1fced34d26718423ea42f9cdb4b264d67c36fa9d78608e319fcd88239c085a3`
- baseline executable SHA-256: `ecf95879b272842c574acddfb735da7c0ed920c1d8d1803be50b40f9acf8d450`

Diagnostics-off candidate JSON and Markdown are byte-identical to those baselines. A full representative Core test runs an observation-only snapshot and B1 evaluation, then proves unchanged question/evidence sequence, posterior, classifications, stopping, selected deck, predictive masks, and final result. The opt-in bank evaluations operate on immutable values and cannot update assessment caches or the production RNG.

Two identical causal runs produced byte-identical semantic JSON and Markdown; timing JSON is deliberately separate. Final semantic JSON SHA-256: `ead10efb51def1dc07e93831672b4f9ea102c643dd23466384b7fe9862647f65` at the time of the final post-checkpoint generation. A second manifest that removed all 4,096-world replicas preserved every inventory, truth fingerprint, potential-response fingerprint, natural/fixed question and evidence path, and ordinary evaluator artifact.

The evaluator addresses document construction, item residuals, learner theta, learner/item truth, potential responses by reader/document/item/occasion, B1 latent draws, B2 theta positions, B2 latent draws, and success sampling with separate labeled seeds. Bank A remains production's inventory-derived bank and is recorded by exact theta/mask fingerprints. There is no parallel causal runner in this milestone, so serial/parallel agreement is not claimed.

## Development diagnostic result

The retained development run is intentionally small and gate-ineligible: eight runs total, with all eight full item tables retained, seven natural successes, one natural miss, and four common-question/common-evidence replay directions. Five runs deliberately bypassed a natural `targetCoverageStable` stop to reach 60 questions. The other three naturally reached all 60 items. No run was dropped; the fixed-budget paths did not improve or worsen realized projected coverage in this sample.

The sole natural miss was `response-noise:reader-0:document-0`: assessable mass 13,273; missed mass 997; realized projected coverage 0.924885; shortfall 0.055115. All missed mass was answered and partitioned as 997 mass with erroneous `verifiedKnown` evidence. Four missed unknown items carried mass 534, 217, 159, and 87; their response draws were within the declared response-noise region. This is observed generator provenance, not proof that response noise is the unique real-world cause.

Across the 24 retained natural production-deck replicas per bank size:

| Contrast | Samples | Mean lower-bound difference | Replica/run range |
| --- | ---: | ---: | ---: |
| B1 − A | 512 | -0.000860 | -0.006178 to 0.003315 |
| B1 − A | 4,096 | -0.001199 | -0.006103 to 0.002336 |
| B2 − A | 512 | -0.001849 | -0.010096 to 0.002712 |
| B2 − A | 4,096 | -0.000948 | -0.004370 to 0.002712 |
| B2 − matched B1 | 512 | -0.000989 | -0.008740 to 0.007685 |
| B2 − matched B1 | 4,096 | 0.000251 | -0.001658 to 0.002110 |

The signs vary across replicas/runs and the 4,096-world B2/B1 mean is near zero. With only two readers and two documents, these results are inconclusive: they do not establish systematic selection optimism, model misspecification, or a release-quality rate. The adverse response-noise run and all null comparisons remain in the artifact.

## Timing evidence

The semantic artifact excludes wall-clock values. On the fixed 8-run/60-lemma workload, raw current-host observations were:

| Phase | Repetitions | Mean ms | Range ms |
| --- | ---: | ---: | ---: |
| Snapshot construction | 16 | 0.827 | 0.658–1.091 |
| All B1 banks for one path (two sizes × three replicas × two deck roles) | 16 | 55.173 | 48.480–60.064 |
| All B2 banks for one path (two sizes × three replicas × two deck roles) | 16 | 54.012 | 48.086–59.528 |
| Bidirectional common-evidence replay per reader/document | 2 | 13.009 | 12.738–13.280 |
| Semantic JSON serialization | 3 | 97.687 | 97.350–98.042 |

The paired diagnostics-off process benchmark retained nine raw repetitions per executable. Means were 462.701 ms baseline and 458.878 ms candidate, a -3.823 ms (-0.83%) delta with exact output parity. Host load was visibly variable, so this is evidence of no material detected overhead, not a performance improvement. Diagnostic work is excluded from the product's 150 ms answer-to-next-card gate.

## Verification

Fresh passing commands:

- `swift test --filter VocabularyAssessmentCausalDiagnosticsXCTests` — 11 tests, 0 failures.
- `swift test --filter AdaptiveVocabularyAssessmentXCTests` — 38 tests, 0 failures.
- `swift test --filter VocabularyMeasurementModelsXCTests` — 6 tests, 0 failures.
- `./scripts/test_vocabulary_assessment_evaluator.sh` — deterministic standard and causal reruns, self-tests, validator, and negative controls passed.
- `python3 scripts/validate_vocabulary_causal_diagnostic_report.py docs/plans/vocabulary-validation-evidence/diagnostic-development-report-v1.json --self-test` — report and four validator negative controls passed.
- Production baseline/current `cmp` checks — JSON and Markdown byte-identical with diagnostics off and during opt-in causal execution.
- Same-manifest causal `cmp` checks — semantic JSON and Markdown byte-identical; changed-bank-size coupling comparison passed.
- `./scripts/check.sh --no-build` — all checks passed, including Core portability/ownership, native-reader access, strict Swift 6 warnings-as-errors build, 154 Swift tests (one expected private-fixture skip), 281 logic tests, evaluator tests, and the remaining deterministic validators.

`./scripts/build_app.sh` was not run because this slice changes no app assembly, resources, framework linkage, UI, or native-reader behavior. The strict package build inside the integrated check compiled the app target. The local wiki generator succeeded; the broader `update_wiki.sh` helper's optional GitHub-wiki clone could not authenticate with the host's SSH key, which does not affect the local generated indexes or product checks.

## Artifacts

- [Frozen development manifest](diagnostic-development-manifest-v1.json)
- [Machine-readable semantic report](diagnostic-development-report-v1.json)
- [Concise mechanism report](diagnostic-development-report-v1.md)
- [Raw diagnostic timing report](diagnostic-development-timing-v1.json)
- [Diagnostics-off paired overhead report](diagnostics-off-overhead-v1.json)

The final semantic, concise, timing, and overhead artifact SHA-256 values are respectively `ead10efb51def1dc07e93831672b4f9ea102c643dd23466384b7fe9862647f65`, `7156911e300d1d5c36fb7dc882835211d1eb87137cf3cc12c974a76409fbd36d`, `94bdb290a9bad44c594e6858d2bff301110bc1b0a8f445d8bae4efaca4823688`, and `250e0d432904dfdbf121b12130f966d64b900e31a72752f176eef1270041c113`.

## Remaining limits and recommendation

- The run is diagnostic-development only and far too small for two-percentage-point conclusions or clustered uncertainty estimation.
- Development-confirmation execution is intentionally absent and no confirmation outcomes were consumed. The frozen release holdout and version-2 golden remain untouched.
- Common-evidence controls use the existing explicitly labeled oracle-informed warm prior. They do not exercise `VocabularyReaderPriorStore`; that belongs to the next longitudinal milestone.
- No skipped or excluded items occurred in the development run, although deterministic fixtures cover skipped, excluded, empty, zero-miss, high-frequency, noisy-known, invalid, and unreachable-budget cases.
- The fixed-budget sample reached 60 items for every run; it found no fixed-budget realized-coverage change, so it provides no evidence that more questions help under these particular draws.

Recommendation: the causal-diagnostic infrastructure is ready to support the next longitudinal-warm slice. That next slice should first connect the existing real isolated reader-prior store/completion path, preserve this manifest/fingerprint separation, add coherent multi-document histories and store failure/idempotency cases, and choose a precision-supported development design before interpreting warm non-inferiority. This recommendation is not permission to begin that slice.
