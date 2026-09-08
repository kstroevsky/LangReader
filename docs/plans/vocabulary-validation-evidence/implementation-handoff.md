# Implementation handoff: synthetic causal diagnostics only

Use this document as the task prompt for the implementing mode. The current task prepared and refined the plan; it did not implement the milestone. The user's latest instruction was to stop before writing code and hand over these instructions.

## Task and stop boundary

Implement only the first execution milestone in the [refined implementation plan](implementation-plan.md): **synthetic causal diagnostics**. Complete a small end-to-end, independently verified diagnostic tool, then stop for review. Do not continue automatically into longitudinal warm simulation or any later milestone.

The authorized slice includes:

- Failed-deck forensic records and exact occurrence-mass conservation.
- Frozen-deck evaluation with unchanged production A, B1 and B2 predictive banks.
- Reproducibility, independent RNG streams and paired potential-response controls.
- Fixed-deck/fixed-bank controls and small-enumeration oracle fixtures with independently hand-calculated/reference expectations.
- Natural, fixed-budget and common-question/common-evidence counterfactual infrastructure where directly required by the diagnostics.
- Narrow tests, production-output parity evidence, diagnostic overhead measurement and a checkpoint report.

Do not implement study-data schema changes, the human study, production selector changes, warm-production changes, the longitudinal-warm milestone, POS policy changes, calibration slots, new production model dimensions, release-holdout tuning or a golden replacement. Do not collect participant data, drive the live GUI, publish/commit/push, or modify user databases for this slice. Preserve existing authorized work and stop at the checkpoint below.

## Read before editing

Repository: `/Users/a.stroevskaya/Desktop/dev/LangReader`.

1. Read applicable `AGENTS.md`, `CONTEXT.md`, `docs/architecture/DESIGN.md`, and the refined plan plus its latest verification/revision artifacts.
2. Read the canonical `docs/plans/vocabulary-measurement-coherence-authorized/candidate-roadmap.md`, acceptance, and ledger where the slice touches a contract. The canonical roadmap SHA-256 remains `b218edcb4deff49af2e899553e196d562aa2de0e1a004e49b81bee134ba67512`; its ledger remains 42 active / 12 deferred. The companion plan is not a replacement authority.
3. Inspect `git status`, the current revision and any intervening changes. At handoff preparation, HEAD was `e8ea803c2a9eb557677a520f4c97aacf729e7c52`; the plan directory was untracked user-requested work. Do not delete, overwrite or commit it incidentally.
4. If `.codegraph/` exists, use CodeGraph before broad source searches. Read relevant manifests, wrappers and tests before selecting an implementation seam.
5. Use the code-work skill for implementation and lossless-plan-evolution if a real plan amendment becomes necessary. Do not freely rewrite the accepted plan to fit a convenient implementation.

Useful source entry points:

- `Sources/LeafReaderCore/VocabularyReview/AdaptiveVocabularyAssessment.swift`: `nextQuestion`, `record`, `apply`, `result`, `predictiveCoverageSamples`, `stratifiedThetaSampleIndexes`, `coverageSelection`, `coverageLowerBound`, and posterior snapshots.
- `Sources/LeafReaderCore/VocabularyReview/VocabularyMeasurementModels.swift`: Core-owned latent/observation semantics and production model configuration.
- `scripts/evaluate_vocabulary_assessment.swift`: synthetic document generation, actual difficulty, simulated evidence/truth, development substreams and existing aggregate reports.
- `scripts/evaluate_vocabulary_assessment.sh`, `scripts/build_core_module.sh`, the diagnostic/sensitivity runners, report validator and evaluator self-test.
- `Tests/LeafReaderCoreTests/AdaptiveVocabularyAssessmentXCTests.swift` and `VocabularyMeasurementModelsXCTests.swift`: existing exact parity, stopping, sampling and likelihood fixtures.

The historical warm diagnostic deliberately supplies an oracle-informed prior. Leave it unchanged in this milestone. The future longitudinal implementation must exercise the real store, but no such history/store changes belong here.

## Behavioral and mathematical contract

Production must continue to use its existing 512 predictive samples, deterministic posterior midpoint strata, 121-point theta grid, nine-point difficulty integration, fifth-percentile lower bound, 98% default coverage target, 16-item shortlist, `allNonExcluded + evidenceSurrogate`, exact optimizations and existing stopping/UX.

Preserve the 8/20/80 conditional question limits, eligibility/tail-validation rules, soft evidence, epsilon/reliability separation, exclusions, manual selections, persistence and all reader boundaries. Keep Core mathematical ownership; do not copy or approximate the likelihood in a separate Python implementation.

Preserve all current numerical release gates, the frozen three-seed/eight-document version-3 adverse holdout, version-2 golden, deferred features and completed PR #9 refresh. A successful diagnostic run does not establish release acceptance or real-learner calibration.

Make the diagnostics explicit opt-in. With diagnostics off, do not consume new random draws, change serialization of established golden reports, select different questions, or alter posterior/deck/stopping behavior. With observation-only diagnostics on, the production assessment result and future question path must also remain unchanged.

## Implement an immutable diagnostic boundary

Prefer a narrow snapshot/evaluation seam at the existing Core sampler owner. Capture the exact assessment state, item evidence and inclusion policy, probability curves, posterior and production bank needed for diagnostic evaluation. Keep selected-deck membership fixed for a given comparison. A snapshot is a read-only projection, not a new authoritative assessment or persistence store.

The normal selector, stop checks, result construction and app must not call independent evaluation banks. Diagnostic work must not mutate caches or merge state into the production assessment. Be careful that calling a result helper does not silently reselect a different deck when evaluating an externally supplied frozen set.

Keep shared probability semantics in Core. Synthetic population orchestration, scenario provenance, run manifests, rich forensic serialization and timing reports generally belong in offline tools. Avoid pulling research-only orchestration or AppKit into the domain model. A focused separate diagnostic file is preferable to broad controller/model restructuring, but choose the smallest coherent extension after source inspection.

## A, B1 and B2 semantics

For each frozen assessment/deck, produce the following evaluations:

| Bank | Theta positions | Latent-item draws | Purpose |
| --- | --- | --- | --- |
| A | Exactly the existing production deterministic strata | Exactly the existing production draws/masks | Preserve the bank that constructed the deck and its reported bound |
| B1 | The same production theta strata and relative mass as A | Independent draws, independent of A and other replicas | Isolate Bernoulli/mask-bank effects conditional on the production theta approximation |
| B2 | Independently randomized or shifted stratified posterior positions under a declared scheme | Independent draws, separate from theta jitter and other banks | Evaluate the broader finite predictive approximation |

At the inspected revision, production uses inverse-CDF positions `(s + 0.5) / 512`. For a larger B1 bank, repeat those exact production positions evenly and generate fresh latent-item draws. Do not silently substitute midpoint strata at a larger sample count: that changes the theta approximation and breaks the intended B1 control. Restrict B1 sizes to compatible repetition counts or explicitly document and validate an equivalent mass-preserving design.

For B2, choose and document one reproducible stratified randomization scheme before outcomes. Independent within-stratum jitter is one candidate. Verify its posterior sampling semantics, zero-mass/boundary handling and independence from item draws. The seed must influence the randomized theta positions as well as independently addressing latent draws.

The earlier suggested 4,096 and 16,384 worlds are diagnostic candidate sizes, not required production settings or approved new gates. Freeze sample sizes, replicas, seed derivation and diagnostic comparison rules in a run manifest before inspecting results. Do not select a favorable replica. Record all replicas, bank definitions, posterior/selection fingerprints and numerical variability.

Evaluate the same selected set and assessable denominator across A/B1/B2. Include decks fixed independently of A and a declared sample of successful production decks as controls, not only failures. Report the fifth-percentile coverage, predicted target-miss probability where computed, A-to-B1 and B1-to-B2/A-to-B2 differences, and replicate/sample-size variability.

A single A-pass/B-fail pair is not causal proof. A single hidden-truth miss with agreeing banks is not proof of misspecification. Investigate systematic discrepancies across banks, replicas, readers and documents, separating numerical variability from model uncertainty and population variability. Diagnostics may end inconclusively.

## Forensic records and exact conservation

Generate a summary for every run. Retain detailed missed-item records and a predeclared success comparison sample, or all item records if practical. Do not retain only favorable results.

Capture synthetic reader/document/scenario IDs; inventory/truth/response fingerprints; seed/stream and source/configuration provenance; true theta; estimated posterior/interval; questions, evidence and validation metadata; natural/fixed-budget/replay mode; natural stop/bypassed-stop information; selected set; excluded mass; expected and conservative coverage; realized coverage; bank results; and relevant difficulty/noise/flip provenance.

For each missed unknown item record lexical identity, occurrence count, final P(known), answered/unasked/skipped state, evidence category/ordinal, difficulty prior mean/SD/source/version, actual synthetic difficulty/effective residual and idiosyncratic-flip information. Distinguish observed generator provenance from an inferred causal label. If an existing generator combines/clamps difficulty components, name the reported residual honestly or retain the components without changing established generation.

For included items j with occurrence weights w_j, hidden knowledge K_j and fixed selected set D:

```text
W = sum_j w_j
missedMass = sum_j w_j * 1[K_j = 0 and j not in D]
realizedProjectedCoverage = 1 - missedMass / W
targetShortfall = max(0, 0.98 - realizedProjectedCoverage)
```

Use exact integer mass accounting before converting to proportions. The answered and unasked partitions must sum exactly to missedMass. Answered evidence-category partitions must also conserve their parent total. Flip/noise/residual mechanism flags may overlap: do not present their raw percentages as an additive decomposition without a predeclared exclusive rule.

Specify zero-denominator behavior and claim eligibility. Report excluded/rejected mass separately; never improve a metric by silently dropping hard items. Protect against invalid weights, missing truth, duplicate keys, incompatible selection/snapshot identities, impossible bank shapes and non-finite probabilities. Invalid diagnostic input must be rejected explicitly rather than coerced into a passing result.

## Reproducibility and experiment separation

Separate RNG streams for document generation, item residuals, learner truth, potential response errors, bank-A production sampling, B1 latent draws, B2 theta positions, B2 latent draws, and any success-record subsampling. Keep the frozen production/release evaluator's sequential stream unchanged.

For paired counterfactuals, address potential responses by learner, document/session, lexical item and response occasion, rather than consuming response noise only by the chosen question ordinal. Verify both truth and potential-response fingerprints. A different selector or a diagnostic-bank count must not silently create a different synthetic learner or response table.

Reports should be deterministic given source/configuration/seeds. Separate wall-clock timing/host-load observations from deterministic semantic JSON so reproducibility checks remain meaningful. Prefer versioned new diagnostic artifacts over incompatible changes to frozen output shapes. Record dirty-tree identity or source hashes accurately; do not invent a clean revision.

The refined plan has three evaluation partitions:

1. Freely used diagnostic-development material.
2. Fresh synthetic development-confirmation seeds/documents, untouched during iterative design, used only after a diagnostic/model candidate is frozen.
3. The existing frozen release holdout, unchanged and not used as a tuning loop.

Do not run the release holdout in this first checkpoint. Do not consume development-confirmation outcomes while designing the diagnostic implementation. If a runner for confirmation is outside this slice, state that clearly; preserve the plan's future freeze boundary and do not label ordinary development data confirmation. Freeze/reject/amend decisions must retain adverse evidence rather than recycle a viewed set into an untouched claim.

## Counterfactual infrastructure

Implement only what the first diagnostics directly need:

- Natural run using the untouched product policy, with a saved natural result and complete evidence path.
- Explicit development-only continuation to a declared feasible budget, never beyond 80 scored questions; retain natural stops that were bypassed. Exclusions, skipped/answered items and candidate exhaustion remain enforced. Record unreachable budgets rather than manufacturing duplicate answers or dropping those runs.
- Common-question/common-evidence replay with the same order, evidence and defined validation metadata. Preserve both source-path directions when comparing two paths. Do not pick only the favorable replay sequence.

Do not globally weaken `isFinished`, modify the production selector, or inject a new stopping mode into the app. A copy-based diagnostic wrapper or narrowly named diagnostic API may reuse existing selection/update owners; validate that any bypass affects only the deliberate diagnostic call. Consider whether existing restoration/replay facilities suffice before adding a new API.

Matched budgets still leave question-selection confounding. Common replay isolates posterior effects only conditional on its fixed evidence path. Distinguish diagnostic metadata semantics from authentic reader-serving question assignments. Preserve negative or nonmonotone results; more questions are not assumed to improve every realized deck.

## Verification requirements

Establish a reproducible baseline before source changes. Existing baseline artifacts from handoff preparation may exist at `/tmp/leafreader-causal-baseline.json`, `/tmp/leafreader-causal-baseline.md` and `/tmp/leafreader-causal-baseline-executable`, generated with seed 42, two readers, two documents and 60 lemmas. These are disposable aids, not durable acceptance evidence; recreate/verify them against the actual starting revision if necessary. The small run is gate-ineligible and cannot establish release quality.

Required tests and evidence:

1. Production diagnostics-off versus baseline: same deterministic JSON/Markdown where contractually unchanged, plus direct question/evidence/posterior/classification/stopping/deck/mask parity through representative natural runs. Aggregate metric equality alone is insufficient.
2. Observation-only diagnostics on/off: unchanged production result and subsequent question path; no bank-B mutations or RNG consumption in the normal path.
3. A parity: diagnostic evaluation of the frozen production selection reproduces its exact mask-derived coverage/quantile.
4. B1: production theta positions/masses are identical, independent latent draws vary with replica seed, and larger supported sample counts preserve those positions/masses.
5. B2: reproducible stratification, independent theta/latent streams, correct inverse-CDF handling, seed variation and unchanged truth/evidence tables.
6. Mass conservation: hand-calculated fixtures for answered/unasked errors, exclusions, an overwhelmingly frequent missed item, zero misses and empty/ineligible populations; invalid input tests.
7. Fixed-bank/fixed-deck and small-enumeration controls: independent expected totals/quantiles, not two invocations of the same helper. Define a genuinely independent small oracle; exact empirical-bank enumeration must not be mislabeled an exact full posterior oracle.
8. Counterfactuals: natural stop preserved, deliberate stop bypass logged, 80 ceiling/exhaustion enforced, duplicate answers prevented and replay metadata/posteriors tested.
9. Reproducibility: identical artifacts for identical manifests; independence/coupling fingerprints; serial/parallel agreement if parallel execution is supported; changed sample count cannot change synthetic truth or potential responses.
10. Overhead: separately measure snapshot construction, B1, B2, counterfactual replay and serialization on fixed workloads, retaining all repetitions and source/environment metadata. Assess diagnostics-off overhead against the starting executable. Do not mix diagnostic workload time into the product's 150 ms benchmark and claim a regression, or omit it from the diagnostic-cost report.

Run the narrow affected Core/oracle suites while iterating, with strict Swift 6 and warnings-as-errors. Inspect standalone wrapper flags: do not assume every existing script passes the same strict flags as SwiftPM. Extend the existing evaluator self-test/validation integration only as needed; keep expensive diagnostic experiments opt-in.

Before handoff run `./scripts/check.sh --no-build` when the environment permits. Run the app assembly build only if the actual change affects app assembly/resources/framework linkage/UI; none is intended in this slice. Investigate and report genuine environment/pre-existing failures rather than weakening checks. Preserve frozen goldens, resource manifests and native-access allowlists. Do not regenerate unrelated documentation or fixtures just to silence a failure.

## Checkpoint report and mandatory stop

Provide a durable checkpoint report and concise user summary containing:

- Changed files and the purpose/owner of each change.
- Mathematical/statistical invariants, including A/B1/B2 semantics, exact mass denominator, likelihood reuse and interpretation limits.
- Production parity proof with diagnostics off and observation-only diagnostics on; baseline/source identification and artifact links.
- Deterministic/RNG independence and reproducibility tests, fixed-bank and small-oracle evidence.
- Narrow test commands/results and the integrated check result or precise blocker.
- Diagnostic overhead, diagnostics-off comparison, raw repetitions and host/configuration limitations.
- Development diagnostic results with uncertainty and retained adverse/null cases; no claim that all coverage causes or human validity are solved.
- Design issues discovered, including any scope-boundary limitation or evidence still missing.
- Recommendation whether the infrastructure is ready for the next longitudinal-warm slice, and what would need correction first.

Stop after delivering that report. Do not implement longitudinal histories, amend study schemas, enable calibration, tune a selector or consume the release holdout without the user's next instruction.
