# Vocabulary measurement, personalization, and calibration roadmap

## Summary

Evolve Prepare Vocabulary without replacing its adaptive CAT architecture. Deliver in ordered stages:

1. Fix answer validity and replace infallible direct outcomes with probabilistic evidence.
2. Add uncertain item-difficulty priors and posterior-predictive coverage.
3. Introduce lemma+POS lexical identities and a guarded local cross-book reader prior.
4. Add experimental domain resources and auto-detection without changing production difficulty.
5. Add privacy-preserving research export and offline empirical calibration tooling.
6. Keep same-POS sense splitting, domain blending, and empirical parameters disabled until their validation gates pass.

No response telemetry or automatic upload is added.

## Core model and assessment changes

- Replace `VocabularyAssessmentOutcome` with versioned `VocabularyKnowledgeEvidence`:

  - `verifiedKnown`, reliability 0.97.
  - `typedVerifiedKnown`, reliability 0.98.
  - `verifiedUnknownOrPartial`, reliability 0.98 toward unknown.
  - `reportedUnknown`, reliability 0.95 toward unknown.
  - `unsure`, reliability 0.75 toward unknown.
  - `legacyKnown`, reliability 0.75.
  - `legacyUnknown`, reliability 0.85.
  - `excluded`, no ability update.

- Treat these as synthetic cold-start observation coefficients, not calibrated accuracies. For evidence reliability `r` and latent item probability `p`, update θ with the noisy-observation likelihood rather than forcing the item to 0 or 1. Cap effective reliability at `1 - errorFloor`, allowing validation contradictions to soften prior direct evidence.

- Calculate an answered item’s displayed `P(known)` by Bayes-updating its item prior with its evidence. Preserve evidence labels separately from estimated classifications; use:

  - Verified known.
  - Reported unknown.
  - Not sure.
  - Estimated known only at `P ≥ 0.85`.
  - Estimated unknown only at `P ≤ 0.15`.
  - Otherwise uncertain.

- Keep validation questions at 15, 20, 25, and so on. Compute fractional contradiction evidence for `unsure`; retain the Beta(1,19) error-floor estimate and `0.05...0.25` clamp.

- Introduce `VocabularyItemDifficultyPrior` containing mean, standard deviation, source, and version. Change `DocumentVocabularyDifficultyProviding` to return this prior instead of a fixed scalar.

  - Ranked words: existing logit-rank mean; `σ = 0.35 + 0.40 × rankPercentile`.
  - Unranked words: mean 4, `σ = 1.5`.
  - Empirically calibrated items: fitted mean with `σ = max(0.15, standardError)`.
  - Integrate difficulty uncertainty with fixed nine-point Gaussian quadrature and cache the resulting response curves.

- Replace the current coverage approximation with deterministic posterior-predictive coverage:

  - Use 512 stratified samples from the 121-point θ posterior.
  - Sample item difficulty and latent knowledge with a stable seed derived from inventory identity and algorithm version.
  - Preserve exclusions, soft answer evidence, and selected-for-learning items in every sample.
  - Report the fifth percentile of sampled lexical-token coverage.
  - Build the deck greedily by worst-tail shortfall reduction, then remove redundant cards until the set is locally minimal.
  - Use exact enumeration/branch-and-bound for small oracle fixtures; report approximation regret and never claim global minimality for large inventories.

- Retain the 16-item expected-loss shortlist and exact global-loss evaluation. Cache posterior-predictive samples so 10,000-lemma answer-to-next-card p95 remains within 150 ms.

## Lexical identity, personalization, and app flow

- Add `VocabularyLexicalItemID(language, lemma, partOfSpeech, senseKey?)` and normalized `VocabularyPartOfSpeech`. Extend the document index to request `.lexicalClass`, accepting POS only when the leading hypothesis is at least 0.65 and exceeds the next hypothesis by 0.20; otherwise use `.unknown`.

- Group by lemma+POS. Keep `senseKey` nil in production. Existing lemma-only Vocabulary Records act as wildcard matches and are never duplicated or destructively split. Add compatible SQLite columns for lexical key and POS; old records remain readable.

- Reserve a `VocabularySenseDisambiguating` boundary. Same-POS context clustering remains disabled until an English/German labeled fixture demonstrates macro-F1 of at least 0.85 and oversplitting below 2%.

- Change assessment UX:

  - Initially show only lemma, optional POS, and `I know it`, `Not sure`, `I don’t know`, and `Not a word/name`.
  - `I know it` reveals meaning/context and requires `My meaning was correct` or `No / only partly` before consuming an answer.
  - `Not sure` and `I don’t know` record evidence immediately, count as answers, then reveal learning content with Continue.
  - If lookup fails after `Not sure`/`I don’t know`, Retry/Skip affects only the definition; the answer remains counted.
  - If lookup fails after `I know it`, verification remains pending and does not count until successfully verified or abandoned.
  - Optional typed mode stores the short response locally, displays it beside the revealed definition, and still requires self-verification; no AI grading occurs.

- Migrate existing sessions to algorithm version 3:

  - Old known/unknown answers become explicit weak legacy evidence.
  - Recompute every posterior, classification, and deck.
  - Preserve exclusions, final manual selection, and already-created Vocabulary Records.
  - Keep Start Over available.

- Add language-scoped `VocabularyReaderPrior` tables to `personal-vocabulary.sqlite3`, separate from exposure-based vocabulary statuses. Only completed assessment evidence updates them; exposure counts and current “likely known” statuses remain excluded.

- Warm-start from the local reader posterior by mixing 90% of a Gaussian-smoothed stored posterior (`σ = 0.35`) with 10% of the generic prior. Permit an eight-question minimum only when the prior is no older than 180 days, contains at least two completed sessions and 40 verified answers, and the current session includes two tail validations. Otherwise retain the 20-question minimum.

- Enable local cross-book adaptation by default. Add Vocabulary settings showing per-language session/evidence counts and last update, with Reset actions. Shelf removal clears document preparation state but not the language profile.

## Domain and empirical calibration infrastructure

- Add `VocabularyDocumentDomain` metadata: general, literary, news, and technical/reference. Production difficulty continues ignoring this field.

- Add compact, checksummed experimental rank resources:

  - English literary: pinned Google Books English Fiction 2020 one-grams.
  - German literary: pinned Google Books German 2020 one-grams.
  - English/German news and reference: pinned Leipzig News and Wikipedia corpora.
  - Retain top 200,000 valid forms per domain with source/version/attribution metadata.

- Put domain auto-detection, picker, and difficulty blending behind a developer-only experimental flag. Suggest a domain from normalized document cross-entropy; fall back to general when the best-vs-second score margin is below 5%. Do not enable production blending until empirical held-out gates pass. Google permits reuse of Ngram data, while Leipzig downloadable corpora are CC BY. [Google Books Ngram](https://books.google.com/ngrams/info), [Leipzig terms](https://www.wortschatz.uni-leipzig.de/en/usage)

- Add explicit research export from Vocabulary settings:

  - Generate a disclosed, resettable random participant pseudonym.
  - Optionally include L1 language code and broad self-rated proficiency.
  - Export language, lexical item ID, POS, domain metadata, difficulty features/versions, evidence type, protocol version, and session ordinal.
  - Exclude document ID/title, context, file path, exact timestamps, typed meanings, definitions, and identity/account data.
  - Preview included fields before atomically saving the export.
  - Never transmit automatically.

- Add offline tools to validate/merge exports, fit shrinkage Rasch item difficulties, calculate standard errors/item fit/DIF, compare Rasch with 2PL on participant-held-out folds, and generate a versioned `VocabularyItemCalibrationPack`.

- Production may load only reviewed bundled calibration packs. Include an item only after at least 100 independent pseudonymous learners and standard error no greater than 0.35. Flag or exclude items with material L1/proficiency DIF. Keep 2PL disabled unless participant-held-out log loss improves by at least 0.01 with stable discrimination estimates.

## Testing, measurements, and rollout gates

- Core tests cover evidence likelihoods, soft direct probabilities, legacy migration, contradiction smoothing, difficulty quadrature, deterministic posterior samples, exact small coverage oracles, deck deletion, POS grouping, wildcard migration, warm-prior eligibility, and 8/20/80 limits.

- App tests cover both quick and typed flows, verification before scoring, immediate unknown/unsure recording, lookup retry/skip behavior, restoration, local-profile reset, transactional schema migration/import, research-export privacy, and unchanged PDF/Web reader boundaries.

- Extend the simulator with verified-response confusion matrices, warm multi-book readers, difficulty uncertainty, POS ambiguity, and current-versus-new protocol comparisons. Retain existing gates and require:

  - Well-specified ECE ≤ 0.05 and θ interval coverage of 85–95%.
  - Well-specified and item-residual coverage hit rate ≥ 95%.
  - Response-noise coverage hit rate ≥ 90%.
  - Idiosyncratic-knowledge coverage hit rate ≥ 85%.
  - Coverage-deck precision ≥ 0.50 in every synthetic scenario.
  - No scenario’s Brier/ECE may degrade by more than 0.01 from its newly reviewed golden.
  - Warm-start question count improves by at least 25% without coverage-hit degradation above two percentage points.

- Domain blending remains experimental until participant-held-out real-response evaluation improves Brier by at least 0.005, worsens ECE by no more than 0.005, and does not reduce coverage-hit rate by more than two percentage points in either language.

- Keep Release gates at 150 ms p95 for 10,000-lemma answer-to-next-card and 16 ms real-app main-thread uninterrupted work. Add posterior-sampling, POS-indexing, warm-start, migration, and export benchmarks.

- Deliver as green staged commits: evidence/UX protocol; difficulty and posterior coverage; POS/schema migration; local reader prior; experimental domain resources; research export/fitter; evaluator/performance gates; documentation. Run focused suites after each stage, then the full evaluator, Release benchmarks, six-document GUI matrix, `./scripts/check.sh --no-build`, and `./scripts/build_app.sh`.

## Assumptions

- The adaptive expected-loss CAT remains one-dimensional Rasch-like until real residual analysis justifies otherwise.
- Selected learning cards are treated as known in post-learning coverage simulations; the UI continues to say this is lexical coverage, not comprehension.
- Soft verified-known items may be proposed in coverage mode when their residual uncertainty materially prevents the target; they are visibly labeled and remain editable.
- Cross-book adaptation uses only assessment evidence, never passive exposure history.
- Real learner calibration, domain blending, same-POS sense splitting, and 2PL parameters remain inactive until their stated gates pass.
