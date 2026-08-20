# Prepare Vocabulary real-learner validation pilot

## Purpose

Synthetic evaluation cannot establish whether LeafReader probabilities describe
real people. This pilot is the minimum empirical study needed before describing
the model as calibrated or treating its 98% lower bound as a validated learner
confidence statement.

The pilot evaluates three separate claims:

1. predicted `P(known)` agrees with independently verified pre-reading word
   knowledge;
2. the proposed deck captures enough of the reader's unknown, high-occurrence
   document vocabulary;
3. after learning the deck, verified lexical-token coverage reaches the target
   without an excessive number of unnecessary cards.

Comprehension is a separate outcome. A short reading-comprehension measure may
be collected exploratorily, but 98% lexical coverage must never be reported as
98% comprehension.

## Participants and documents

- Recruit consenting English and German learners across declared L1 and broad
  proficiency strata.
- Use multiple document genres and all supported formats. Document text, title,
  path, and context stay outside research exports unless a separate study
  consent explicitly authorizes them.
- Split by participant **and** document. No reader, document, or near-duplicate
  text used for fitting may appear in final evaluation.
- Keep an untouched confirmatory set until the protocol, scoring rubric, and
  model version are frozen.

Item calibration packs retain the production eligibility requirements: at least
100 independent pseudonymous learners per lexical item, standard error no more
than 0.35, and no material L1/proficiency DIF.

## Independent knowledge criterion

The criterion is collected before LeafReader reveals a definition or book
context.

1. Show lemma and POS only.
2. Ask the participant to type the book-relevant meaning or a translation.
3. Store the response only in the consented study dataset, never in the normal
   privacy-preserving product export.
4. Score against a frozen bilingual rubric using two trained human raters who
   cannot see LeafReader's probability or deck decision.
5. Resolve disagreements by adjudication and report inter-rater agreement.

Self-verification remains the production interaction, but it is not the
independent ground truth for this study. Automatic AI grading may be studied
later; it must not define the pilot criterion without a separate validation.

Use a delayed subset retest to estimate response instability and learning or
fatigue effects. Randomize item order and use alternate context-free prompts so
the retest is not simple visual recognition.

## Sampling the document inventory

A latent ability estimate can be evaluated from a sample, but exact item-level
knowledge cannot be inferred for every unasked word. The study therefore uses
two cohorts:

- **Small-document audit:** verify every assessable lexical item, providing a
  direct realized-coverage and deck-regret measure.
- **Large-document stratified audit:** test every selected card plus a
  probability-, frequency-, POS-, and occurrence-stratified sample of unselected
  items. Retain inclusion probabilities and use weighted estimates with
  confidence intervals. Do not treat the sampled fraction as a complete item
  census.

The unselected audit must include high-confidence predicted-known and
predicted-unknown tails. Otherwise calibration errors in the exact regions used
for early stopping remain invisible.

## Study sequence

1. Record consent, language, optional L1, broad proficiency, and anonymous
   participant identifier.
2. Build the document inventory and freeze the algorithm/model version.
3. Run the independent pre-reveal criterion on the audit sample.
4. Run Prepare Vocabulary without exposing criterion labels to the algorithm.
5. Record questions, evidence, probabilities, stop reason, diagnostics, and
   editable proposed deck.
6. Teach/review the selected deck using a standardized learning interval.
7. Re-test selected items and the reserved unselected audit sample.
8. Administer the delayed stability/retention subset.
9. Evaluate only after participant/document splits and exclusions are frozen.

## Primary metrics and acceptance

Report all metrics by language and important L1/proficiency strata, with
participant-clustered uncertainty intervals.

- Brier score, log loss, reliability diagram, and ECE for pre-reading
  `P(known)`.
- Calibration slope/intercept and coverage of the reported theta interval.
- Deck precision and occurrence-weighted recall against verified unknown items.
- Realized lexical-token coverage after verified learning, with a lower
  confidence bound for sampled large inventories.
- Rate at which the nominal 98% deck misses actual 98% coverage.
- Question count, stop-reason distribution, definition failures, abandon rate,
  and time burden.
- Warm-versus-cold question reduction with coverage non-inferiority.
- Differential item functioning and subgroup calibration.

Before data collection, freeze numerical product gates in a timestamped study
protocol. Do not derive them from the confirmatory results. Synthetic thresholds
remain engineering regression gates and are reported separately.

## Fitting and model comparison

- Fit shrinkage Rasch item difficulties only on the training participants.
- Tune regularization and optional features on participant-held-out validation
  folds.
- Evaluate once on the untouched participant-and-document holdout.
- Compare frequency-only, generic Rasch, warm-prior Rasch, and empirical-item
  variants. Include simple baselines such as frequency threshold and “select all
  unranked words.”
- Keep 2PL disabled unless participant-held-out log loss improves by at least
  0.01 and discrimination estimates are stable.
- Keep domain blending and sense splitting disabled until their separate gates
  pass on both languages without material subgroup regression.

## Privacy and governance

Normal LeafReader exports remain explicit, local, pseudonymous, and omit typed
meanings, documents, contexts, definitions, paths, titles, exact timestamps, and
account identity. A research study needing criterion responses or document
linkage requires separate informed consent, retention limits, access controls,
and a deletion procedure. No automatic upload or passive learner telemetry is
introduced by this pilot plan.

## Interpretation

A successful pilot supports claims only for the studied protocol, populations,
languages, documents, and model version. It does not prove exact unknown-word
detection, universal 98% coverage, or comprehension. Failed or subgroup-specific
results must remain visible and may require wider uncertainty, more questions,
or disabling personalization for affected conditions.
