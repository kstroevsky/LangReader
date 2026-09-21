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
2. Ask the participant to type one or more context-free meanings or
   translations. Do not show book context or identify a target sense.
3. Store the response only in the consented study dataset, never in the normal
   privacy-preserving product export.
4. Score against a frozen bilingual rubric using two trained human raters who
   can see the restricted target sense/context but cannot see LeafReader's
   probability or deck decision. Credit the response when any supplied meaning
   matches that target.
5. Preserve `criterion-ambiguous` separately from missing and from
   unknown-or-partial. Resolve disagreements by adjudication and report
   agreement before adjudication plus ambiguity/missingness rates.

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
- **Large-document stratified audit:** before assessment or deck exposure,
  select a probability sample from the complete eligible inventory using frozen
  positive inclusion probabilities and probability-, frequency-, POS-, and
  occurrence-based strata. Use the selected cards that fall inside this
  predetermined audit sample to estimate deck precision/recall with the frozen
  design weights. Do not post-hoc add every selected card or treat the sampled
  fraction as a complete item census.

The unselected audit must include high-confidence predicted-known and
predicted-unknown tails. Otherwise calibration errors in the exact regions used
for early stopping remain invisible.

## Pretest interference gate

Confirmatory collection remains blocked until an explicitly developmental,
consented interference study is complete. Within participant/document, randomly
assign otherwise eligible audit items to criterion-before-product versus no-
criterion-before-product, stratified by frozen frequency/POS features. Compare
the first unaided production response before reveal. Freeze the estimator,
dependence treatment, missingness rules, and practically meaningful interference
margin before inspecting results. Material interference requires split-sample,
order, or carryover handling in the confirmatory design; the criterion must not
simply be assumed inert.

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
- Calibration slope/intercept. Literal theta-interval coverage remains a
  synthetic model-recovery gate and is omitted from confirmatory human claims
  unless an independently defensible latent reference instrument is approved
  and its uncertainty is modeled.
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

## Calibration assignment design

The approved design interpretation is a 7.5% independent Bernoulli opportunity
at each eligible non-tail scored ordinal, in expectation—not a forced 5–10%
quota in every session. Short sessions may contain zero assignments. Tail
validation and existing question limits remain unchanged, and production
activation remains disabled pending the separate schema/operational freeze.

Use a protocol-frozen reusable anchor bank to create item overlap. In ordinary
Prepare Vocabulary an anchor is eligible only when that lexical item occurs in
the current document. A separately consented calibration study may use a broader
anchor block. Preserve the recorded pool/support snapshots and conditional/joint
propensities; do not sample arbitrary book vocabulary uniformly or lower pack,
DIF, or 2PL gates.

Confirmatory collection also requires a separately reviewed and approved
[Statistical Analysis Plan](VOCABULARY_VALIDATION_SAP_TEMPLATE.md). It must
freeze the estimand, weighting estimator, inclusion-probability treatment,
participant/document clustering, variance or interval method, missing-data
rules, multiplicity policy, outcomes/gates, and analysis populations before
confirmatory data are collected and before confirmatory outcomes are inspected.
The roadmap deliberately does not select those statistical methods.

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

The Core `ConsentedValidationStudyDataset` is a separate explicit-consent
contract. Validate a serialized dataset before study analysis with:

```sh
python3 scripts/validate_vocabulary_validation_study.py /path/to/study.json
```

The validator rejects product document fields, invalid rater/adjudication or
sampling metadata, and participant or opaque-document leakage across training,
validation, and confirmatory splits. It validates design inputs; it does not
choose or execute the SAP's estimator or uncertainty method.

## Interpretation

A successful pilot supports claims only for the studied protocol, populations,
languages, documents, and model version. It does not prove exact unknown-word
detection, universal 98% coverage, or comprehension. Failed or subgroup-specific
results must remain visible and may require wider uncertainty, more questions,
or disabling personalization for affected conditions.
