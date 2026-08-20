# Prepare Vocabulary: model and measurement contract

For the complete test-layer map, metric definitions, run commands, acceptance
gates, and current blocker-remediation plan, see
[`vocabulary-preparation-testing/README.md`](vocabulary-preparation-testing/README.md).

`Prepare Vocabulary` is an optional pre-reading workflow for English and German
PDF, EPUB, and DOCX documents. It builds a lemma+part-of-speech inventory, asks
8–80 answer-before-reveal questions (20 minimum without an eligible local
reader prior), and proposes ordinary Vocabulary Records for
review. Open it from the **Words** window with **Prepare Vocabulary**, or accept
the non-blocking offer shown after a supported document first becomes readable.

The feature has two modes:

- **Estimate all unknown words** selects confirmed unknown lemmas and unasked
  lemmas whose estimated probability of being known is below 0.5.
- **Target 98% coverage** selects the smallest occurrence-weighted deck that
  reaches the model's conservative lexical-token coverage target.

The result is editable before **Create & Review** performs one atomic,
idempotent import and opens the existing Review Session. Already-saved lemmas
are shown but never duplicated or modified.

## What the estimates mean

Answers are probabilistic evidence, not infallible labels. `I know it` is not
scored until the definition is revealed and the reader verifies their meaning;
typed mode still uses self-verification and never sends or AI-grades the typed
meaning. Unknown and unsure answers are recorded before revealing learning
content. Versioned synthetic reliability coefficients update the reader and
item posterior through a noisy-observation likelihood. They are engineering
cold-start assumptions, not measured human accuracies. Exclusions update
neither ability nor coverage.

The cold-start model is a deterministic one-parameter Rasch-like model. English
difficulty priors use the pinned ECDICT rank scale, whose maximum rank is
47,062. German priors use the pinned 200,000-row Leipzig
`deu_news_2025_1M` scale. The best rank among a lemma and its observed
inflections determines the mean prior. Ranked items have rank-dependent prior
uncertainty; unranked items use mean difficulty 4 with standard deviation 1.5.
Nine-point Gaussian quadrature integrates that uncertainty. Document count affects question
importance and output ordering, not general-language difficulty.

These probabilities are **frequency-based model estimates**, not probabilities
calibrated from LeafReader learners. They do not identify a reader's exact
unknown vocabulary and do not guarantee comprehension. In particular:

- no meaning embedding or semantic-neighbor propagation is used;
- a valid-looking unranked word remains a candidate with the hardest prior;
- lexical identities are lemma+POS when Natural Language supplies a sufficiently
  dominant class; legacy lemma-only records remain wildcard matches;
- same-POS sense splitting remains disabled pending a labeled English/German
  fixture with macro-F1 at least 0.85 and oversplitting below 2%;
- self-scoring, definition quality, proper names, specialist language, and
  idiosyncratic knowledge remain sources of error;
- 98% is estimated lexical-token coverage after learning the proposed deck,
  not 98% comprehension.

Coverage mode uses 512 deterministic posterior-predictive samples over reader
ability, item difficulty, soft answer evidence, and latent item knowledge. The
reported lower bound is the fifth percentile of lexical-token coverage. Small
fixtures use exact enumeration; large inventories use worst-tail greedy
selection followed by redundant-card deletion and therefore report
approximation regret rather than global minimality.

Completed assessments update a separate local per-language reader posterior;
passive exposure and existing “likely known” statuses never enter it. Warm start
requires two completed sessions, 40 verified answers, freshness within 180 days,
and two current-document tail validations. It mixes 90% of the smoothed local
posterior with 10% of the generic prior. Profiles can be reset in Vocabulary
settings.

Experimental literary/news/reference corpora and domain detection are available
only behind `LeafReader.experimentalVocabularyDomains`. The picker records
metadata, while production difficulty remains general-language. Domain blending,
same-POS sense splitting, and 2PL parameters stay inactive until their documented
held-out gates pass.

Results expose the stop reason, reader-ability estimate and interval,
conservative coverage, residual uncertain-lemma mass, skipped definitions,
final expected-loss reduction, and whether the 80-question limit was reached.
Definition skips remain uncertain but cannot be selected again, count as an
answered question, or prevent clean exhaustion.

## Deterministic quality evaluation

Run the fixed-seed evaluator and validate it against the checked-in golden
report:

```sh
./scripts/evaluate_vocabulary_assessment.sh \
  --seed 20260820 --readers 64 --documents 8 --lemmas 400 \
  --json /tmp/vocabulary-quality.json \
  --markdown /tmp/vocabulary-quality.md

python3 scripts/validate_vocabulary_assessment_report.py \
  /tmp/vocabulary-quality.json \
  --baseline docs/perf/vocabulary-assessment-quality-baseline.json
```

The evaluator covers both assessment modes for well-specified Rasch,
item-residual, response-noise, and idiosyncratic-knowledge populations with a
Zipf-like occurrence distribution. It includes verified-response confusion
matrices, uncertain item difficulty, POS ambiguity, and eligible warm multi-book
readers. It reports Brier score, log loss, ten-bin
ECE, reader-ability RMSE and 90% interval coverage, deck precision/recall,
realized token coverage, target misses, oracle deck regret, question count, and
stop-reason distributions.

The checked-in golden report is still algorithm version 2 and is not an accepted
baseline for version 3. The three-seed/eight-document version 3 holdout recorded:

| Metric | Result | Gate |
|---|---:|---:|
| Aggregate ECE | 0.0238–0.0268 | no more than 0.05 |
| 90% ability-interval coverage | 89.06%–94.53% | 85%–95% |
| Well-specified coverage hit rate | 100% | at least 95% |
| Response-noise coverage hit rate | **87.5%–96.88%** | at least 90% |
| Idiosyncratic coverage hit rate | **84.38%–92.19%** | at least 85% |
| Minimum deck precision | 0.5521–0.5580 | at least 0.50 |
| Warm-start question reduction | 83.48%–85.68% | at least 25% |

One fixed development seed passes its synthetic engineering gates, but the
three-seed/eight-document version 3 release holdout does not. Only one holdout
seed passed; the failures include idiosyncratic coverage hit at 84.375%,
response-noise coverage hit at 87.5%, and warm coverage degradation of 4.6875
percentage points. The raw report is
[`vocabulary-assessment-holdout-v1.json`](vocabulary-assessment-holdout-v1.json).
The version 2 golden remains intentionally unreplaced. All synthetic populations
remain robustness diagnostics rather than claims of real-learner calibration.

## Explicit research export and empirical calibration

Vocabulary settings can preview and atomically save a local research JSON file.
Nothing is uploaded automatically. The user may provide an optional L1 code and
broad proficiency and may reset the disclosed random pseudonym. Exports contain
lexical ID/POS, domain metadata, versioned difficulty features, evidence type,
protocol version, and session ordinal. They exclude document identity/title,
path, context, definitions, typed meanings, exact timestamps, and account data.

Validate, merge, fit shrinkage Rasch difficulties, inspect item fit/DIF, and
compare regularized 2PL on participant-held-out folds offline:

```sh
python3 scripts/fit_vocabulary_calibration.py \
  /path/to/export-*.json \
  --output-pack /tmp/vocabulary-calibration.json \
  --output-report /tmp/vocabulary-calibration-report.json
```

Tool output is always `reviewed: false` and cannot affect production. A reviewed
bundled Rasch pack can contribute an item only with at least 100 independent
pseudonymous learners, standard error no greater than 0.35, and no material
L1/proficiency DIF. 2PL stays disabled unless participant-held-out log loss
improves by at least 0.01 with stable discrimination.

Evaluator and validator self-tests run in `./scripts/check.sh --no-build`.
Changing the algorithm requires regenerating and deliberately reviewing both
golden artifacts rather than merely accepting new numbers.

## Assessment response-time benchmark

Run the optimized fixed-workload benchmark with:

```sh
./scripts/benchmark_vocabulary_assessment.sh \
  /tmp/vocabulary-assessment-benchmark.json
```

It records 8 warm-up advances followed by 30 raw samples for 100, 1,000, 5,000,
and 10,000 lemmas in both modes, plus a 10,000-item warm start and auxiliary
POS-indexing, migration, and privacy-export timings. Three no-build 2026-08-21
Apple Silicon Release repetitions recorded these 10,000-item ranges:

| Mode/profile | p50 range | p95 range | Maximum range |
|---|---:|---:|---:|
| All unknown / cold | 15.32–45.29 | 16.80–52.26 | 17.86–53.34 |
| Coverage / cold | 25.78–81.29 | 28.78–137.19 | 29.56–141.19 |
| Coverage / warm | 29.91–96.94 | **33.17–155.69** | 34.16–279.85 |

The 150 ms gate is not accepted because one of three warm repetitions failed.
The first post-build capture was more unstable still, with cold coverage p95 at
201.2 ms. Raw samples and environment/source metadata are retained in
`vocabulary-assessment-benchmark.json` and
`vocabulary-assessment-benchmark-series.json`; favorable repetitions are not
selected in isolation.

Inventory construction depends heavily on Natural Language and hardware, so it
is a same-machine trend rather than a portable absolute gate. Reproduce the
300-page, approximately 90,000-token workload with:

```sh
./scripts/benchmark_vocabulary_index.sh 300 2000 5
```

The 2026-08-15 Apple Silicon before measurement built the 300-page index in
4,140.62 ms. Five complete 90,000-token occurrence lookups had a 266.57 ms
median (263.97–416.98 ms observed range); single common-lemma and missing-lemma
lookups had 0.393 ms and 0.235 ms medians respectively. Compare future captures
on the same machine and OS rather than treating these values as cross-machine
CI limits.

## Real-app capture and GUI smoke

Copy `vocabulary-preparation-fixtures.example.json` to a private, gitignored
manifest and supply English and German PDF, EPUB, and DOCX fixtures. The
preparation capture compares document-visible-ready time with a same-machine
control and fails above `baseline + max(10%, 50 ms)`. It also requires
main-thread uninterrupted-work p95 at or below 16 ms while measuring inventory
build, assessment advance, results, and import events. German automation uses
the injected fixture dictionary and never the network.

```sh
LEAFVOCAB_UI_SMOKE=1 \
  ./scripts/check_vocabulary_preparation_smoke.sh \
  /private/path/vocabulary-preparation-fixtures.json
```

The script intentionally refuses to run without the opt-in environment
variable, an explicit private manifest, and macOS Accessibility permission.
Private documents, paths, learner answers, and research exports must not be
committed. Version 3 stores no telemetry and never transmits response logs.
