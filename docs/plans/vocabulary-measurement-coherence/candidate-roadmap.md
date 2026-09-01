# Vocabulary measurement, personalization, and calibration roadmap

## Summary

Evolve Prepare Vocabulary without replacing its adaptive CAT architecture. Deliver in ordered stages:

1. Fix answer validity and replace infallible direct outcomes with probabilistic evidence.
2. Add uncertain item-difficulty priors and posterior-predictive coverage.
3. Introduce lemma+POS lexical identities and a guarded local cross-book reader prior.
4. Add experimental domain resources and auto-detection without changing production difficulty.
5. Add privacy-preserving research export and offline empirical calibration tooling.
6. Keep same-POS sense splitting, domain blending, and empirical parameters disabled until their validation gates pass.

Stages 1–6 are the retained, already implemented baseline capabilities and constraints. They remain prerequisites and are not a second delivery sequence. The priority list below is the binding order for the next implementation phase.

The next implementation phase is measurement coherence rather than another production modeling dimension. Execute it in this order:

- **Priority 0 — observation and calibration consistency:** separate latent person-item exceptions from response reliability, make the offline fitter use the production evidence likelihood, and collect calibration-purpose assignment metadata.
- **Priority 0 — release validity:** diagnose the failing multi-seed holdout without weakening gates, strengthen DIF, and create a consented participant-and-document validation dataset distinct from the normal privacy export.
- **Priority 0/1 — warm and performance robustness:** validate warm non-inferiority, replace abrupt prior expiry only after drift is estimable, and stage expensive predictive coverage work so the full calculation is reserved for candidate stops and final results.
- **Priority 1 — validated predictors and UX:** validate POS identity, test domain and lexical features as residual difficulty predictors, standardize research covariates, and distinguish current from projected post-mastery coverage.
- **Priority 2 — deferred expansion:** add high-value multi-word lexical items before book-local same-POS sense splitting; consider empirical risk calibration only after the independent pilot.

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

- Treat these as synthetic cold-start observation coefficients, not calibrated accuracies. For evidence reliability `r` and latent item probability `p`, update θ with the noisy-observation likelihood rather than forcing the item to 0 or 1.

- Split the current `errorFloor` role into two explicit parameter families:

  - `εknowledge` represents person-item exceptions and other misspecification in `P(K_j | θ, b_j)`.
  - `ρverifiedKnown`, `ρtypedVerifiedKnown`, `ρverifiedUnknownOrPartial`, `ρreportedUnknown`, `ρunsure`, `ρlegacyKnown`, and `ρlegacyUnknown` represent `P(E | K_j, evidenceType)`.
  - Extract the production latent-knowledge function from `Sources/LeafReaderCore/VocabularyReview/AdaptiveVocabularyAssessment.swift` symbols `adjustedProbability` and `baseItemProbability` at source SHA-256 `5ff417329db82f4ad655e444927f51adaa07f7d79b674121a028107a9b990166` into a versioned `VocabularyKnowledgeModel`; rename only its model-misspecification parameter to `εknowledge` and do not change the function’s mathematical form in this separation stage. If the source hash differs before implementation, stop and rebaseline this requirement against the reviewed code rather than inferring a replacement formula.
  - Use the evidence-specific `ρ` values only in the observation likelihood. Do not flatten latent knowledge and cap response reliability with one shared parameter.
  - Preserve the existing evidence coefficients as versioned synthetic priors until independently scored pilot responses estimate or supersede them.

- Make a versioned Core `VocabularyObservationModel.evidenceLikelihood(evidence, latentKnownProbability)` the single normative implementation of the categorical observation likelihood, extracted without mathematical change from `AdaptiveVocabularyAssessment.swift` symbol `evidenceLikelihood` at the same source SHA-256. Runtime posterior updates and answered-item reconstruction call it directly. The offline fitter consumes a generated observation-model manifest plus golden likelihood fixtures produced from that same Core implementation; it must not maintain an independently authored hard/fractional mapping or formula.

- Calculate an answered item’s displayed `P(known)` by Bayes-updating its item prior with its evidence. Preserve evidence labels separately from estimated classifications; use:

  - Verified known.
  - Reported unknown.
  - Not sure.
  - Estimated known only at `P ≥ 0.85`.
  - Estimated unknown only at `P ≤ 0.15`.
  - Otherwise uncertain.

- Keep validation questions at 15, 20, 25, and so on. Compute fractional contradiction evidence for `unsure`; retain the Beta(1,19) estimate and `0.05...0.25` clamp for `εknowledge`. Tail-validation mismatches update `εknowledge`; independently criterion-scored responses estimate evidence-specific `ρ` values. A tail mismatch must not directly redefine every evidence category’s reliability.

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

- Keep the current 180-day eligibility rule until an empirical drift parameter is frozen. Then replace the validity cliff with time-dependent uncertainty diffusion on the existing grid: `θt ~ Normal(θt-1, σdrift² × Δt)`. Convolve the stored 121-point posterior with the elapsed-time Gaussian before the existing 90%/10% mixture. Do not enable the diffused prior unless participant-and-document held-out warm coverage is non-inferior by the existing two-percentage-point gate and question burden still improves by at least 25%.

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
  - Optionally include L1 language code and a pre-assessment bounded self-rated proficiency value: `A1/A2`, `B1/B2`, `C1/C2`, or `Unknown / prefer not to say`.
  - Export language, lexical item ID, POS, domain metadata, difficulty features/versions, evidence type, protocol version, and session ordinal.
  - When an explicitly enabled research-mode calibration slot is asked, additionally export `questionOrdinal`, `selectionType`, `predictedKnownBeforeAnswer`, and `thetaBinBeforeAnswer`.
  - Define `selectionType` as `initialCalibration`, `adaptiveLoss`, `tailValidation`, or `calibration`.
  - Exclude document ID/title, context, file path, exact timestamps, typed meanings, definitions, and identity/account data.
  - Preview included fields before atomically saving the export.
  - Never transmit automatically.

- Add offline tools to validate/merge exports, fit shrinkage Rasch item difficulties, calculate standard errors/item fit/DIF, compare Rasch with 2PL on participant-held-out folds, and generate a versioned `VocabularyItemCalibrationPack`.

- Make the offline fitter use the same categorical observation likelihood as production: consume the generated `VocabularyObservationModel` manifest from the hash-locked Core source above and pass every golden likelihood fixture before fitting `P(Eij | θi, bj, ρE)`. Do not map evidence to hard or fractional target values or author a second likelihood. Keep the runtime evidence coefficients as fixed versioned priors for exploratory fitting; estimate them only from independently criterion-scored pilot data. Report the observation-model and reliability source/version in every calibration pack.

- Separate reader-serving item selection from calibration-data collection:

  - Normal production sessions retain the current adaptive-loss and tail-validation policy.
  - An explicitly consented research mode reserves a protocol-frozen rate within 5–10% of scored questions for calibration/exploration assignments.
  - Calibration assignments target underrepresented ability ranges for items encountered in the current document; they do not request unrelated document text or transmit data automatically.
  - Freeze and version the slot rate and assignment policy before confirmatory collection. Keep calibration slots disabled until the selected assignment design has an approved versioned export schema that lets the offline fitter reconstruct or condition on the assignment mechanism. The four listed research fields are the minimum schema, not a claim that every future assignment design needs no additional metadata. Do not tune the assignment design on the confirmatory holdout.

- Replace the current residual-mean DIF eligibility heuristic before using DIF as a production fairness claim:

  - implement logistic-regression DIF and/or a Rasch likelihood-ratio procedure;
  - distinguish uniform from non-uniform DIF;
  - report effect sizes as well as significance;
  - control multiple comparisons;
  - perform iterative anchor purification;
  - enforce frozen minimum group sizes;
  - analyze L1 and proficiency separately rather than only concatenated `L1|proficiency` groups.

- Add a separate `ConsentedValidationStudyDataset` contract. It may contain an opaque study document ID, independently scored criterion label, rater/adjudication fields, question assignment metadata, randomized audit inclusion probability, and delayed-retest linkage only under explicit study consent. It must exclude ordinary file paths, titles, account identity, and raw document text. Confirmatory tooling must enforce both participant disjointness and document disjointness; the normal `ProductResearchExport` remains privacy-minimized and cannot be used to claim a document-held-out validation.

- After sufficient real responses exist, fit difficulty hierarchically with partial pooling. Candidate predictors include general frequency, prevalence, contextual diversity, word length, morphology, POS, L1 cognateness, and domain-frequency residuals. Sparse items borrow strength from the feature model; well-observed items increasingly use empirical item difficulty. Fit feature coefficients and item effects on training participants/documents, tune on validation participants/documents, and evaluate on the untouched participant-and-document holdout.

- Test domain information as residual difficulty evidence rather than as a hard document label. After accounting for general frequency and the frozen lexical feature set, evaluate fiction/news/reference frequency deltas on participant-and-document holdouts. If the existing domain gates pass, use detector scores as `P(domain | document)` and integrate over domain uncertainty; do not introduce an arbitrary fixed blend.

- Production may load only reviewed bundled calibration packs. Include an item only after at least 100 independent pseudonymous learners and standard error no greater than 0.35. Flag or exclude items with material L1/proficiency DIF. Keep 2PL disabled unless participant-held-out log loss improves by at least 0.01 with stable discrimination estimates.

- Do not interpret every supported L1 difference as item bias or silently discard it. After proper DIF analysis and sufficient per-group support, evaluate an explicitly versioned L1-conditioned residual `bj,L1 = bj + δj,L1` on held-out participants/documents. Keep it disabled unless it improves predictive loss and coverage without subgroup calibration regressions.

## Real-learner validation execution

- Freeze a consented English/German pilot protocol before collecting confirmatory data. The independent knowledge criterion occurs before LeafReader reveals a definition or document context:

  1. show lemma + POS;
  2. request a typed book-relevant meaning or translation;
  3. score against a frozen bilingual rubric with two blinded human raters;
  4. adjudicate disagreements and report inter-rater agreement.

  Production self-verification remains low-friction and optional typed recall remains optional; neither is reused as the independent criterion label.

- Recruit multiple English/German learner, L1, and proficiency strata and multiple genres/formats. Freeze an untouched confirmatory set. The final split must be disjoint by participant and opaque study document ID.

- Use complete lexical audits for small documents. For large documents, test every selected card plus a probability/frequency/POS/occurrence-stratified sample of unselected items. Store each item’s audit inclusion probability and use weighted estimates with uncertainty intervals. Add a delayed stability/retention retest.

- Report Brier score, log loss, calibration plot/ECE, calibration slope/intercept, θ-interval coverage, deck precision, occurrence-weighted unknown-item recall, realized post-learning lexical-token coverage, nominal-98% miss rate, question/time burden, warm-versus-cold non-inferiority, inter-rater agreement, DIF, and subgroup calibration. Reading comprehension is a separate exploratory outcome and is never inferred from lexical coverage.

- Fit and tune only on training/validation participants and documents. Keep the participant-and-document confirmatory holdout untouched during fitting and tuning, then use it for final evaluation. Synthetic gates remain separately labeled engineering diagnostics.

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

- Keep the current failing three-seed/eight-document version-3 release holdout frozen as adverse evidence. Do not weaken its gates or replace the version-2 golden with a favorable development result. Add a diagnostic matrix that separately varies:

  The locked baseline has only 1/3 seeds passing every gate: idiosyncratic coverage hit falls to 84.375%, response-noise coverage hit falls to 87.5%, warm coverage degrades by as much as 4.6875 percentage points, and several cold profiles still consume essentially all 80 questions. These values are blockers, not tuning targets.

  1. evidence reliability;
  2. `εknowledge`;
  3. item-difficulty prior standard deviation;
  4. posterior-predictive coverage quantile;
  5. warm-prior mixture weight.

  For every experiment, report whether the failure originates in the latent knowledge model, observation model, warm prior, or coverage-deck decision. Use development seeds for diagnosis; run the untouched release holdout only after freezing the candidate. Retain failed and null experiments.

- Validate POS identity independently with licensed English and German Universal Dependencies fixtures. Report POS precision, recall, abstention rate, language/genre strata, noun↔verb errors, adjective↔participle errors, and resulting lexical-item split/merge error. Keep the production `unknown` fallback. Treat the current 0.65 probability and 0.20 margin as engineering thresholds until this evaluation is complete.

- Domain blending remains experimental until participant-held-out real-response evaluation improves Brier by at least 0.005, worsens ECE by no more than 0.005, and does not reduce coverage-hit rate by more than two percentage points in either language.

- Keep Release gates at 150 ms p95 for 10,000-lemma answer-to-next-card and 16 ms real-app main-thread uninterrupted work. Add posterior-sampling, POS-indexing, warm-start, migration, and export benchmarks.

- Stage posterior-predictive computation before changing sample counts:

  Preserve the current repeated benchmark evidence: one warm 10,000-item coverage run reaches 155.69 ms p95 and therefore exceeds the existing 150 ms gate. Do not select only favorable repetitions.

  - every scored answer updates the θ posterior, cached item probabilities, and cheap next-question shortlist;
  - build the full 512-sample conservative coverage deck only when a stop is otherwise eligible and for final results;
  - optionally evaluate a 128-sample screening approximation for deciding whether to attempt a full stop check;
  - evaluate 1024 samples only as a measurement candidate, not a new production default;
  - accept staged screening only if empirical comparison with the full path shows that the release decision does not change more than the accepted tolerance;
  - keep all benchmark repetitions and profile the frequency and phase of full deck recomputation before further optimization.

- Deliver as green staged commits: evidence/UX protocol; difficulty and posterior coverage; POS/schema migration; local reader prior; experimental domain resources; research export/fitter; evaluator/performance gates; documentation. Run focused suites after each stage, then the full evaluator, Release benchmarks, six-document GUI matrix, `./scripts/check.sh --no-build`, and `./scripts/build_app.sh`.

## Product coverage behavior and empirically gated options

- Immediately clarify coverage wording without changing the default target:

  - label the action **Build a deck for 98% projected coverage**, not “Reach 98% coverage”;
  - show `Estimated current coverage` separately from `Projected after mastering selected words`;
  - continue stating that creating a card does not demonstrate mastery and lexical coverage is not comprehension.

- After real participant-and-document validation estimates target-specific miss rates, evaluate three user goals: Light preparation at 95%, Comfortable reading at the recommended/default 98%, and Maximum lexical support at 99%. Do not attach comprehension percentages. Do not expose a target whose empirical risk and deck burden have not been reported by language, genre, and proficiency stratum.

- Do not reduce the cold ceiling merely because 80 questions feels long. After the observation model is coherent, evaluate explicit burden/uncertainty modes:

  - Quick: approximately 25–35 questions with wider residual uncertainty;
  - Balanced: approximately 40–60 questions;
  - High confidence: up to 80 questions.

  Formalize stopping as `expected reduction in decision loss / (λ × question cost)`. Keep the current 20-question cold minimum and 80-question maximum until a replacement mode passes the real and synthetic gates.

## Deferred lexical and risk extensions

- Add high-value multi-word lexical items before enabling same-POS sense clustering. Candidate classes include phrasal verbs, idioms, lexical phrases, and compounds whose meaning is not recoverable from independently known component words. Keep production use disabled until a separately approved MWU design and validation plan exists.

- If sense splitting proceeds afterward, make it book-local: split a lemma+POS only when the current document uses meaningfully incompatible contextual clusters. Use clustering only as a proposal mechanism and retain the existing macro-F1 ≥ 0.85 and oversplitting < 2% gates. Do not map every occurrence to a global dictionary sense inventory.

- Defer empirical risk calibration until an untouched real validation set exists. Then evaluate an outer conformal/risk-control safety margin over the Bayesian deck decision to correct systematic optimism under model misspecification. Keep it inactive unless the calibration split, exchangeability assumptions, monotone loss, desired miss rate, and held-out coverage guarantee are all frozen and reported.

## PR #9 description refresh

- Replace the materially stale PR #9 body with the complete **New Pull Request description** in `review-2026-08-25.md` (SHA-256 `f5299abc0c32aa5fb1af34068aaad74e069d08bb274c455f737e06de2379bc5c`). Preserve that source payload verbatim except for repository-generated links or measured status values that are revalidated immediately before publication. The new body must describe answer-before-reveal evidence, uncertain difficulty, posterior-predictive coverage, lemma+POS identity, local personalization, gated domains/calibration, failed version-3 holdout/performance status, privacy boundaries, and the real-learner validation path. Do not publish the earlier authoritative-answer/reveal-first description.

## Assumptions

- The adaptive expected-loss CAT remains one-dimensional Rasch-like until real residual analysis justifies otherwise.
- Selected learning cards are treated as known in post-learning coverage simulations; the UI continues to say this is lexical coverage, not comprehension.
- Soft verified-known items may be proposed in coverage mode when their residual uncertainty materially prevents the target; they are visibly labeled and remain editable.
- Cross-book adaptation uses only assessment evidence, never passive exposure history.
- Real learner calibration, domain blending, same-POS sense splitting, and 2PL parameters remain inactive until their stated gates pass.
- Typed meaning recall remains optional in production. Independent criterion-scored typed recall belongs to the consented validation study and is not reused as production self-verification ground truth.
- Self-rated proficiency remains a research covariate and never becomes a strong production θ prior without separate held-out validation.
- No new production modeling dimension is enabled while the observation likelihood, calibration assignment, DIF analysis, release holdout, or warm/performance gate remains unresolved.
