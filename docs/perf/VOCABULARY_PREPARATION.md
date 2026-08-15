# Prepare Vocabulary: model and measurement contract

`Prepare Vocabulary` is an optional pre-reading workflow for English and German
PDF, EPUB, and DOCX documents. It builds a document lemma inventory, asks 20–80
reveal-and-self-score questions, and proposes ordinary Vocabulary Records for
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

Direct assessment outcomes are authoritative. A confirmed-known lemma has
probability 1, a confirmed-unknown lemma has probability 0 until selected for
learning, and an excluded token is removed from loss and coverage calculations.
Only unasked lemmas use the model posterior.

The cold-start model is a deterministic one-parameter Rasch-like model. English
difficulty priors use the pinned ECDICT rank scale, whose maximum rank is
47,062. German priors use the pinned 200,000-row Leipzig
`deu_news_2025_1M` scale. The best rank among a lemma and its observed
inflections determines its prior; document occurrence count affects question
importance and output ordering, not general-language difficulty.

These probabilities are **frequency-based model estimates**, not probabilities
calibrated from LeafReader learners. They do not identify a reader's exact
unknown vocabulary and do not guarantee comprehension. In particular:

- no meaning embedding or semantic-neighbor propagation is used;
- a valid-looking unranked word remains a candidate with the hardest prior;
- one lemma produces one card even if the document uses several senses;
- self-scoring, definition quality, proper names, specialist language, and
  idiosyncratic knowledge remain sources of error;
- 98% is estimated lexical-token coverage after learning the proposed deck,
  not 98% comprehension.

For coverage mode, the selection calculation uses the posterior's fifth
percentile reader ability and preserves direct outcomes. It then applies a
one-sided 95% uncertainty margin to the weighted unasked-lemma total. This is a
deliberately conservative engineering bound, not a validated psychometric
confidence interval for the learner population.

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
  --seed 20260815 --readers 64 --lemmas 400 \
  --json /tmp/vocabulary-quality.json \
  --markdown /tmp/vocabulary-quality.md

python3 scripts/validate_vocabulary_assessment_report.py \
  /tmp/vocabulary-quality.json \
  --baseline docs/perf/vocabulary-assessment-quality-baseline.json
```

The evaluator covers both assessment modes for well-specified Rasch,
item-residual, response-noise, and idiosyncratic-knowledge populations with a
Zipf-like occurrence distribution. It reports Brier score, log loss, ten-bin
ECE, reader-ability RMSE and 90% interval coverage, deck precision/recall,
realized token coverage, target misses, oracle deck regret, question count, and
stop-reason distributions.

The 2026-08-15 fixed-seed well-specified gate recorded:

| Metric | Result | Gate |
|---|---:|---:|
| Aggregate ECE | 0.0103 | no more than 0.05 |
| 90% ability-interval coverage | 93.75% | 85%–95% |
| Coverage-mode readers at actual 98% after learning | 100% | at least 95% |
| All-unknown Brier score | 0.1023 | regression no more than 0.01 |
| Coverage-mode Brier score | 0.1137 | regression no more than 0.01 |

The misspecified populations are robustness diagnostics, not acceptance claims.
Their coverage-target miss rates were 3.12% for item residuals, 75% for response
noise, and 15.62% for idiosyncratic knowledge. Those results demonstrate why
the UI must retain uncertainty language and why synthetic validation cannot
replace calibration on consenting learners.

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
and 10,000 lemmas in both modes. The 2026-08-15 Apple Silicon Release capture
recorded these milliseconds:

| Lemmas | All unknown p50 / p95 | Coverage p50 / p95 |
|---:|---:|---:|
| 100 | 0.65 / 0.75 | 0.67 / 1.19 |
| 1,000 | 7.77 / 8.29 | 13.77 / 15.77 |
| 5,000 | 32.03 / 33.56 | 50.39 / 62.88 |
| 10,000 | 79.57 / 85.74 | 113.89 / 140.66 |

The 10,000-lemma p95 gate is 150 ms. Raw samples, OS/toolchain metadata, source
revision, and configuration are stored in
`vocabulary-assessment-benchmark.json`.

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
Private documents, paths, and learner answers must not be committed. Version 1
stores no learner telemetry or cross-user response logs.
