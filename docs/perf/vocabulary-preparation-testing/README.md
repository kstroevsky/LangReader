# Prepare Vocabulary testing and measurement

This document explains how LeafReader tests and measures **Prepare Vocabulary**.
It is both a runbook and an interpretation guide: a green command is useful only
when it is clear which risk that command exercises.

## Current acceptance status

The version 3 implementation is **not release-accepted yet**.

One development seed passed the version 3 synthetic engineering gates, but the
versioned three-seed/eight-document release holdout **fails**. Release acceptance
therefore remains blocked independently of resource verification, the Release
benchmark, integrated checks, and real-app GUI capture:

| Check | Latest result | Required |
|---|---:|---:|
| Well-specified ECE | 0.0238–0.0268 | no more than 0.05 |
| 90% theta-interval coverage | 89.06%–94.53% | 85%–95% |
| Well-specified 98% coverage hit rate | 100% | at least 95% |
| Item-residual coverage hit rate | 95.31%–100% | at least 95% |
| Response-noise coverage hit rate | **87.5%–96.88%** | at least 90% |
| Idiosyncratic-knowledge coverage hit rate | **84.38%–92.19%** | at least 85% |
| Minimum deck precision | 0.5521–0.5580 | at least 0.50 |
| Warm-start question reduction | 83.48%–85.68% | at least 25% |
| Warm-start coverage-hit change | -4.69–-1.56 points | no worse than -2 points |

Only one of three holdout seeds passed. The two failing seeds reached 84.375%
idiosyncratic coverage-hit rate (gate 85%); one also reached only 87.5% under
response noise (gate 90%) and lost 4.6875 percentage points of warm coverage.
See [`../vocabulary-assessment-holdout-v1.md`](../vocabulary-assessment-holdout-v1.md)
and its raw JSON. The checked-in golden remains algorithm version 2 and must not
be replaced with a convenient development seed while this holdout fails.

Synthetic results are not psychometric validation on real learners. They show
that the implementation behaves as intended under declared simulated
populations. Likewise, the 98% target is lexical-token coverage after the
selected cards are treated as learned; it is not a comprehension percentage.

The empirical next step is specified in
[`../../research/VOCABULARY_VALIDATION_PILOT.md`](../../research/VOCABULARY_VALIDATION_PILOT.md):
independent pre-reveal meaning-recall labels, participant-and-document holdouts,
small-document complete audits, stratified large-document audits, and delayed
retesting. Production self-verification is not reused as its own ground truth.

## Measurement layers

The system uses six complementary layers. No single layer is sufficient for a
release decision.

| Layer | Main question | Representative entry points |
|---|---|---|
| Core unit and oracle tests | Are the mathematical and indexing invariants correct? | `AdaptiveVocabularyAssessmentXCTests`, `VocabularyDocumentLemmaIndexXCTests` |
| App integration tests | Does the real workflow preserve async, persistence, dictionary, and import contracts? | `VocabularyPreparationCoordinatorXCTests`, `VocabularyPreparationPersistenceXCTests` |
| Fixed-seed synthetic evaluation | Does prediction and deck selection remain accurate under declared populations? | `evaluate_vocabulary_assessment.sh` |
| Release microbenchmark | Is answer-to-next-card latency bounded as inventory size grows? | `benchmark_vocabulary_assessment.sh` |
| Real-app capture and GUI smoke | Does on-demand preparation avoid reader regressions and work in every supported format/language? | `check_vocabulary_preparation_smoke.sh` |
| Resource and research-tool validation | Are rank tables reproducible and exported research data private/inert by default? | domain/resource tests and `fit_vocabulary_calibration.py --self-test` |

## 1. Core unit, property, and oracle tests

Run the focused Core suites with:

```sh
swift test --filter AdaptiveVocabularyAssessmentXCTests
swift test --filter VocabularyDocumentLemmaIndexXCTests
swift test --filter VocabularyReaderPriorStoreXCTests
swift test --filter GermanFrequencyRankTableXCTests
swift test --filter VocabularyDocumentDomainXCTests
swift test --filter VocabularyResearchExportXCTests
```

These tests cover four groups of invariants.

### Inventory and lexical identity

- English and German inflections group into lemma+POS lexical items.
- Derivations, German compounds, and unrelated neighbors do not collapse.
- Ambiguous POS remains `unknown`; a confident POS needs a leading probability
  of at least 0.65 and a 0.20 margin over the second hypothesis.
- Observed forms, counts, source ranges, PDF line-wrap repair, and deterministic
  ordering are preserved.
- URLs, email addresses, markup/entities, malformed separators, confident names,
  and high-confidence OCR fragments are rejected without using missing frequency
  rank as a reason to reject a valid-looking word.
- Legacy lemma-only records remain wildcard matches and are not duplicated.

### Bayesian assessment mathematics

- Evidence types use their versioned noisy-observation likelihoods instead of
  forcing answered probabilities to zero or one.
- Stronger evidence moves the answered-item posterior farther than weaker legacy
  or unsure evidence.
- The Beta(1,19) contradiction estimate is clamped to 0.05–0.25 and softens
  evidence and unasked predictions.
- Ranked and unranked item-difficulty priors have the specified means and
  standard deviations; nine-point Gaussian quadrature is deterministic.
- Posterior restoration reproduces the same probabilities and theta estimate.
- Exclusions leave both the loss and coverage denominator. Definition deferrals
  remain uncertain but cannot be selected as questions again.
- First questions span difficulty octiles; tail validation cadence and
  deterministic fallback behavior are checked.
- The 8/20/80 question limits and every stop reason are checked.

### Question selection

For an unasked item with knowledge probability `p`, classification uncertainty
is:

```text
min(p, 1 - p)
```

The all-unknown global loss is the sum of this value across assessable lexical
items. Coverage mode multiplies it by document occurrence count. Tests calculate
the expected global loss after both possible answers and verify that the selected
question maximizes the expected reduction within the deterministic shortlist.

### Posterior-predictive coverage and deck construction

Coverage uses 512 deterministic stratified samples from the 121-point theta
posterior. Every sample also incorporates item-difficulty uncertainty, soft
answer evidence, and latent item knowledge. A selected learning card is treated
as known in the post-learning sample. The reported conservative coverage is the
fifth percentile of sampled occurrence-weighted coverage.

For fixtures with at most ten items, tests enumerate candidate subsets and
compare the production deck with an exact minimum-cardinality oracle. Large
fixtures verify that the greedy worst-tail construction followed by the deletion
pass is locally minimal: removing any retained card must make the fifth-percentile
coverage fall below the target.

## 2. App integration tests

Run:

```sh
swift test --filter VocabularyPreparationCoordinatorXCTests
swift test --filter VocabularyPreparationPersistenceXCTests
```

The coordinator tests use narrow injected document, dictionary, library, import,
and Review-opening boundaries. They verify:

- equivalent inventory semantics for the PDF snapshot and Web plain-text paths;
- stale document ID, load generation, Web-text generation, request ID, and
  cancellation guards;
- hidden-only definition prefetch and deterministic retry/skip behavior;
- `I know it` does not count until reveal and self-verification;
- unknown/unsure evidence counts before definition lookup completes;
- already-saved wildcard or lexical records are protected;
- successful atomic import opens Review and failed import opens nothing;
- only completed assessments update the separate local reader profile.

Persistence tests use temporary stores to verify document-session round trips,
schema compatibility, idempotency, and transaction rollback. Research-export
tests verify that the local evidence store is idempotent and that encoded exports
omit document identity/title/path, context, definitions, typed meanings, exact
timestamps, and account identity.

## 3. Fixed-seed synthetic quality evaluator

### Running it

A full gate-eligible run uses at least 50 readers and 200 lemmas:

```sh
./scripts/evaluate_vocabulary_assessment.sh \
  --seed 20260820 \
  --readers 64 \
  --documents 8 \
  --lemmas 400 \
  --json /tmp/vocabulary-quality.json \
  --markdown /tmp/vocabulary-quality.md
```

During investigation, `--no-gate` writes the complete report even when a gate
fails:

```sh
./scripts/evaluate_vocabulary_assessment.sh \
  --seed 20260820 --readers 64 --documents 8 --lemmas 400 --no-gate \
  --json /tmp/vocabulary-quality.json \
  --markdown /tmp/vocabulary-quality.md
```

Validate report shape, absolute gates, and regression limits against the reviewed
golden:

```sh
python3 scripts/validate_vocabulary_assessment_report.py \
  /tmp/vocabulary-quality.json \
  --baseline docs/perf/vocabulary-assessment-quality-baseline.json
```

The lightweight evaluator self-test is part of `check.sh`. It checks valid and
invalid report fixtures and runs the evaluator twice with the same small seed,
requiring byte-identical JSON and Markdown:

```sh
./scripts/test_vocabulary_assessment_evaluator.sh
```

### Avoiding synthetic overfitting

A fixed synthetic population is executable specification and stress evidence;
it is not a sample of human vocabulary knowledge. Tuning the assessment against
one seed or one fictional population can make the report green without making
the product more valid.

LeafReader therefore separates two multi-seed suites:

```sh
# Frequent engineering sweep: two derived seeds across mild, nominal, and
# severe fictional mismatch profiles. Diagnostic only; no human-validity claim.
python3 scripts/run_vocabulary_assessment_sensitivity.py \
  --suite development-sweep \
  --output-json /tmp/vocabulary-sensitivity.json \
  --output-markdown /tmp/vocabulary-sensitivity.md

# Expensive release holdout: three version-derived nominal seeds, with every
# constituent engineering gate required to pass. Do not use it for tuning.
python3 scripts/run_vocabulary_assessment_sensitivity.py \
  --suite release-holdout \
  --output-json /tmp/vocabulary-holdout.json \
  --output-markdown /tmp/vocabulary-holdout.md
```

The Priority-0 diagnostic matrix is a separate development-only tool. It runs
paired one-factor-at-a-time perturbations of evidence reliability,
`epsilonKnowledge`, difficulty-prior uncertainty, the conservative coverage
quantile, and warm-prior weight:

```sh
python3 scripts/run_vocabulary_assessment_diagnostic_matrix.py \
  --output-json /tmp/vocabulary-diagnostic-matrix.json \
  --output-markdown /tmp/vocabulary-diagnostic-matrix.md
```

The matrix uses deterministic per-scenario substreams and requires the hidden
synthetic-truth fingerprints to remain identical between every variant and its
same-seed baseline. Production evaluator runs retain the frozen sequential
stream. The matrix has no release-holdout mode, does not enforce or weaken
release gates, and does not rank configurations or select a production
candidate.

Its fixed probes are `0.80/1.05` evidence-reliability scale,
`0.025/0.10` minimum `epsilonKnowledge`, `0.50/1.50` difficulty-prior
standard-deviation scale, `0.025/0.10` coverage quantile, and `0.75/0.98`
warm-prior weight around the unchanged production baseline. `supported` in the
report means that a paired perturbation materially moved a predeclared metric
with consistent direction for that level across development seeds. It is
sensitivity evidence, not proof that the named subsystem is the sole real-world
cause. Null and adverse cells remain in the JSON.

The retained two-seed baseline is
`docs/perf/vocabulary-assessment-diagnostic-matrix-v1.json`, with the concise
human-readable disposition beside it in the matching Markdown file. Regenerate
both only from the source revision recorded inside the report; never replace
them with a favorable subset of experiments.

Seeds are deterministically derived from a versioned suite label, rather than
selected after viewing results. The development sweep varies item-residual
standard deviation, response-error rate, and idiosyncratic item-flip rate. The
release holdout keeps the reviewed nominal parameters and requires each complete
run to pass; it is still synthetic and cannot validate real-person calibration.

Algorithm changes must state whether they were motivated by a mathematical
invariant, real-user evidence, or a synthetic failure. A change justified only
by one synthetic cell is not accepted. Compare development and holdout results,
retain raw per-run reports, and report null or adverse results rather than
changing thresholds after inspection.

### Simulated populations

Every population runs both `all-unknown` and `coverage-98` modes. A gate-eligible
run distributes readers across at least four independently generated documents;
the reviewed workload uses eight. Each document has its own difficulty/occurrence
pairing and Zipf-like token distribution, preventing one convenient synthetic
book from defining the result.

| Population | Perturbation | Risk represented |
|---|---|---|
| Well-specified Rasch | Truth follows the declared model | Implementation correctness under model assumptions |
| Item residual | Additional per-item difficulty residual | Frequency prior misses lexical difficulty |
| Response noise | 12% wrong simulated verified responses plus unsure responses | Hindsight, self-score, and interaction mistakes |
| Idiosyncratic knowledge | 12% of item states are flipped | Interests, profession, personal reading history, and other one-dimensional-model violations |

The evaluator also enables item-difficulty uncertainty, assigns ambiguous POS to
10% of synthetic items, simulates the answer-before-reveal evidence protocol,
and compares cold readers with eligible local warm priors.

### Metrics

Let `p_i` be the model's displayed probability that item `i` is known and `y_i`
be synthetic truth (1 known, 0 unknown).

- **Brier score:** mean squared probability error,
  `mean((p_i - y_i)^2)`. Lower is better.
- **Log loss:** penalizes confident wrong probabilities more strongly,
  `mean(-y_i log(p_i) - (1-y_i) log(1-p_i))`. Lower is better.
- **Ten-bin ECE:** group probabilities into `[0,.1)`, ..., `[.9,1]`, compare each
  bin's mean confidence with its observed known fraction, then weight the
  absolute differences by bin size. Lower is better.
- **Theta RMSE:** root mean squared error between estimated and simulated reader
  ability. Lower is better.
- **90% theta-interval coverage:** fraction of readers whose true theta lies in
  the reported 5th–95th percentile interval. It should be close to 90%, not 100%.
- **Deck precision:** selected unknown items divided by all selected items. This
  measures unnecessary cards.
- **Deck recall:** selected unknown items divided by all truly unknown items.
  Coverage mode need not maximize lemma recall because frequent tokens matter
  more than rare types.
- **Realized token coverage:** occurrence-weighted fraction actually known after
  every selected card is treated as learned.
- **Target miss rate:** fraction of coverage-mode readers whose realized coverage
  is below 98%.
- **Oracle deck regret:** proposed deck cardinality minus a truth-aware
  occurrence-sorted oracle deck cardinality. It is a diagnostic, not proof of a
  global optimum on large inventories.
- **Question count and stop-reason distribution:** reveal failure to stop, excess
  burden, or premature convergence.

### Absolute and regression gates

For gate-eligible reports:

- well-specified ECE must be at most 0.05;
- 90% theta-interval coverage must be 85%–95%;
- well-specified and item-residual coverage hit rates must be at least 95%;
- response-noise coverage hit rate must be at least 90%;
- idiosyncratic-knowledge coverage hit rate must be at least 85%;
- every scenario/mode must have deck precision at least 0.50;
- an eligible warm prior must reduce mean question count by at least 25%;
- warm coverage-hit rate may not degrade by more than two percentage points.

Against a reviewed golden, no scenario/mode may regress in Brier score or ECE by
more than 0.01, and no scenario's coverage-hit rate may fall by more than two
percentage points.

Do not regenerate a golden merely to make a changed algorithm green. First
explain the movement, pass the absolute gates, inspect the Markdown and JSON,
and then deliberately replace both reviewed quality artifacts in one commit.

## 4. Release response-time benchmark

Run the optimized benchmark:

```sh
./scripts/benchmark_vocabulary_assessment.sh \
  /tmp/vocabulary-assessment-benchmark.json
```

It compiles the Core and benchmark with `-O`. For inventories of 100, 1,000,
5,000, and 10,000 lemmas in both modes, it discards eight warm-up advances and
records 30 raw answer-to-next-card samples. The measured interval includes
recording one answer, rebuilding dependent state, and selecting the next card.

The hard gate is:

```text
10,000-lemma cold all-unknown p95 <= 150 ms
10,000-lemma cold coverage-98 p95 <= 150 ms
```

The JSON retains raw samples, p50, p95, maximum, configuration, source revision,
Swift version, OS version, and processor count. It also records a 10,000-item
warm profile plus auxiliary session-migration, 5,000-record research-export,
and 10,000-token POS-indexing timings. Auxiliary values are trends until a
reviewed threshold is defined.

Three no-build 2026-08-21 Release repetitions show substantial host-state
variation. At 10,000 items, cold all-unknown p95 ranged 16.80–52.26 ms, cold
coverage ranged 28.78–137.19 ms, and warm coverage ranged 33.17–155.69 ms.
One warm repetition therefore fails the 150 ms gate. An immediately post-build
cold capture reached 201.2 ms p95. Every raw report is retained in the benchmark
series rather than selecting a favorable repetition. Auxiliary POS/export values
remain background trends, not UI latency budgets.

Inventory building relies heavily on Apple's Natural Language framework and
hardware, so it is measured as a same-machine trend:

```sh
./scripts/benchmark_vocabulary_index.sh 300 2000 5
```

That workload represents 300 pages and approximately 90,000 tokens. Compare it
with the prior capture on the same Mac and OS; do not use an absolute
cross-machine CI limit.

## 5. Real-app capture and six-document GUI smoke

Create a private manifest from:

```text
docs/perf/vocabulary-preparation-fixtures.example.json
```

It must contain English and German PDF, EPUB, and DOCX fixtures. Then run in a
logged-in macOS session with Accessibility permission:

```sh
LEAFVOCAB_UI_SMOKE=1 \
  ./scripts/check_vocabulary_preparation_smoke.sh \
  /absolute/private/vocabulary-preparation-fixtures.json
```

The real-app automation records at least:

- 6 inventory builds;
- 120 assessment advances;
- 6 results presentations;
- 6 atomic imports;
- 6 main-thread uninterrupted-work samples;
- PDF, EPUB, DOCX, and aggregate document-visible-ready samples.

The validator requires main-thread uninterrupted-work p95 at or below 16 ms. It
also compares each visible-ready median with a same-machine control and allows
at most:

```text
control median + max(10% of control median, 50 ms)
```

German automation uses the injected fixture dictionary and does not call the
network. Exit code 3 means the explicit opt-in, manifest, or Accessibility
precondition is unavailable; it is not a product pass.

## 6. Resources, privacy, and offline calibration

### Frequency/domain resources

Resource tests verify installed SQLite row counts, known-word lookup, pinned
source metadata, derived SHA-256 metadata, and detector fallback below a 5%
best-vs-second cross-entropy margin. The app bundle must contain every resource
declared as installed.

The Google Books builder verifies every shard's pinned MD5, strips supported
Google POS suffixes, aggregates duplicate word counts, retains valid word forms,
and requires the exact requested row count before writing SQLite. The Leipzig
builder verifies the archive SHA-256 and exact output row count.

### Research export and fitter

The user explicitly previews and saves research JSON; nothing is transmitted
automatically. The offline fitter can be self-tested with:

```sh
python3 scripts/fit_vocabulary_calibration.py --self-test
```

Fit one or more explicit local exports with:

```sh
python3 scripts/fit_vocabulary_calibration.py \
  /path/to/export-1.json /path/to/export-2.json \
  --output-pack /tmp/vocabulary-calibration.json \
  --output-report /tmp/vocabulary-calibration-report.json
```

Tool output is always `reviewed: false` and therefore inert. Production loading
accepts only a reviewed Rasch pack, and only items with at least 100 independent
pseudonymous learners, standard error no greater than 0.35, and no material DIF.

## Resolved implementation blockers

### Warm-start readers incorrectly hit 80 questions

**Root cause:** coverage stopping currently requires the proposed deck's exact
set of lexical keys to be identical for three consecutive answers. An answer can
remove the just-tested predicted-unknown key or add a newly confirmed-unknown
key while leaving the learning plan's coverage and burden effectively unchanged.
The exact set therefore churns, so both cold and warm readers reach the cap.

The retained fix keeps cold sessions conservative and allows material deck
stability only for a genuinely eligible same-language/current-version local
prior after two current-document tail validations:

1. Compare consecutive decks after normalizing the just-answered item, so the
   expected removal of a verified-known card does not reset stability.
2. Track card count, selected occurrence mass, and the occurrence-weighted
   symmetric difference of the remaining deck. Deck construction independently
   guarantees the fifth-percentile target; results recompute and report it.
3. Count a stable answer only when the target is reached and both deck-cardinality
   change and changed occurrence mass are below reviewed tolerances.
4. A validation contradiction, target loss, or material deck change resets the
   streak and suppresses stopping on that answer.
5. Keep the 8-question warm minimum, two current tail validations, and 80 maximum.

The original evaluator also built its “warm” grid with floating-point `stride`,
which could create 120 points while eligibility required 121, silently executing
the cold path. Grids are now index-derived and the evaluator aborts unless the
requested warm path and validations actually execute. Holdout question reduction
ranges from 83.48% to 85.68%; warm coverage non-inferiority still fails one seed
and remains a release blocker below.

### Literary domain resources were incomplete

**Root cause:** the English and German Google Books literary tables are declared
with `derivedChecksum: pending`; only the English/German news/reference tables
are installed. The English transform previously failed to aggregate tagged and
untagged forms before final ranking, and the German source spans eight very large
shards.

Both resources now contain exactly 200,000 ranks. All source MD5 values, the
German ordered-manifest SHA-256, derived SQLite SHA-256 values, rank continuity,
known-word lookup, and cross-shard POS/base aggregation are tested. The builder
uses bounded workers and versioned local caches without accepting partial shards.

## Current blockers and the correct fixes

### Blocker 1: the synthetic release holdout fails

Only one of three independently derived eight-document holdout seeds passes.
The failed ranges are preserved in
`vocabulary-assessment-holdout-v1.json`; thresholds were not changed afterward.

**Fix:** do not tune to the holdout. Use the real-learner protocol in
`docs/research/VOCABULARY_VALIDATION_PILOT.md` to estimate response reliability,
item calibration, and post-learning coverage on participant-and-document
holdouts. Until that evidence exists, retain frequency-estimate wording,
editable decks, and the failed synthetic robustness status.

### Blocker 2: the Release latency gate is host-state unstable

Three identical no-build repetitions range from 28.78 to 137.19 ms p95 for cold
coverage and 33.17 to 155.69 ms for warm coverage. One warm repetition fails the
150 ms gate; a post-build cold capture reached 201.2 ms. All raw samples are kept
in `vocabulary-assessment-benchmark-series.json`.

**Fix:** rerun in a controlled low-contention session and capture the real-app
main-thread gate. Do not select the favorable repetition. Further code changes
need a profile showing retained algorithm work rather than host scheduling.

### Blocker 3: reviewed quality and performance artifacts are stale

**Root cause:** the checked-in quality golden is algorithm version 2, while the
current algorithm is version 3. Current benchmark documentation also predates
the completed v3 acceptance run.

**Fix:** replace the v2 quality golden only after a reviewed v3 holdout passes.
The validator now rejects comparisons with different seeds, workloads,
algorithm versions, or population parameters. Performance artifacts already
retain the current failed repeated series and should be replaced only by a
controlled, fully disclosed rerun.

### Blocker 4: real-app evidence depends on local GUI prerequisites

**Root cause:** the required six documents are intentionally private and GUI
automation requires a logged-in macOS session with Accessibility access. Those
preconditions are unavailable in headless CI.

**Fix:** create the private six-fixture manifest, grant Accessibility to the
driving shell/app, build the app, and run the opt-in smoke command. Preserve the
control and preparation JSON artifacts and report unavailable fixtures as
unverified, never as passed. If an environment cannot satisfy these preconditions,
the release decision must retain an explicit manual/GUI evidence gap.

### Blocker 5: final repository acceptance has not been run on the integrated tree

**Fix:** after all feature commits are integrated, run in this order:

```sh
swift test --filter AdaptiveVocabularyAssessmentXCTests
swift test --filter VocabularyPreparationCoordinatorXCTests
./scripts/test_vocabulary_assessment_evaluator.sh
python3 scripts/fit_vocabulary_calibration.py --self-test

./scripts/evaluate_vocabulary_assessment.sh \
  --seed 20260820 --readers 64 --documents 8 --lemmas 400 \
  --json /tmp/vocabulary-quality.json \
  --markdown /tmp/vocabulary-quality.md

./scripts/benchmark_vocabulary_assessment.sh \
  /tmp/vocabulary-assessment-benchmark.json

./scripts/check.sh --no-build
./scripts/build_app.sh
```

Run the six-document GUI command separately when its prerequisites are present.
Completion requires the command exit statuses, report files, p50/p95 timings,
document-open comparison, and any skipped GUI prerequisite to be recorded in the
handoff.

## What each green layer does not prove

- Unit tests do not prove the probability model matches real learners.
- A synthetic quality pass does not validate evidence reliabilities, item
  difficulty priors, or the 98% interpretation on people.
- A Release microbenchmark does not prove the AppKit main thread stays responsive.
- A GUI smoke pass does not establish probability calibration.
- Real learner calibration remains absent until users explicitly export data,
  it is reviewed offline, and a bundled calibration pack passes its population,
  error, fit, and DIF gates.

The production wording must therefore continue to say **frequency-based
estimate**, **conservative lexical coverage**, and **residual uncertainty**. It
must never claim exact unknown-word detection or guaranteed comprehension.
