# Prepare Vocabulary confirmatory Statistical Analysis Plan gate

This file is a template and approval gate, not a completed Statistical Analysis
Plan (SAP). It deliberately does **not** choose a weighting estimator,
variance/interval construction, missing-data rule, or multiplicity procedure.
Those choices require separate statistical review and must be frozen before
confirmatory data collection and before anyone inspects confirmatory outcomes.

## Study and analysis identity

- SAP version and immutable checksum:
- Study protocol version and checksum:
- Consent protocol version:
- Vocabulary algorithm/model/observation-manifest versions:
- Assignment-policy version:
- Date approved:
- Named approvers and roles:
- Confirmation that confirmatory outcomes have not been inspected:

## Estimands and populations to freeze

- Primary estimand(s), target population, language, proficiency, genre, and
  document-format scope:
- Training, validation, and confirmatory analysis populations:
- Participant inclusion/exclusion rules:
- Document inclusion/exclusion and near-duplicate rules:
- Item/lexical-population definition:
- Pre-reading, post-learning, and delayed-retest analysis windows:

## Sampling and weighting to freeze

- Small-document census rule:
- Large-document stratified audit design:
- Recorded inclusion-probability definition for every sampled item:
- Selected-card versus unselected-audit treatment:
- Weighting estimator selected for each estimand:
- Treatment of zero, missing, invalid, or changed inclusion probabilities:
- Any weight trimming, normalization, or calibration and its rationale:

The approved SAP must select these methods. This roadmap and template do not
select Horvitz–Thompson, Hájek, or any other estimator in advance.

## Sample size and precision planning to freeze

- Planned participants by language, proficiency stratum, L1 stratum, cohort,
  and analysis split:
- Planned independent documents and near-duplicate groups by language, genre,
  format, and split:
- Anticipated participant, document, item, and repeated-item cluster sizes:
- Expected observations per participant, document, lexical item, and
  item-by-ability/L1/proficiency cell:
- Expected small-document census size and large-document audit sample size:
- Expected audited selected-card support and unselected final-tail support:
- Anticipated refusal, abandonment, criterion nonresponse, ambiguous criteria,
  failed lookup, and delayed-retest attrition:
- Minimum expected nonzero inclusion probability and its source:
- Maximum expected design weight before and after any proposed trimming or
  normalization:
- Expected effective sample size overall and for each primary/subgroup
  estimand, including the exact ESS definition:
- Desired interval precision for calibration, deck precision/recall, realized
  lexical coverage, and nominal-target miss rate:
- Warm non-inferiority margin, expected cold/warm support, and power or precision
  calculation under participant/document dependence:
- Independent learners per lexical item for calibration-pack eligibility and
  expected support for uniform/non-uniform DIF by each frozen group axis:
- Sensitivity of every calculation to the developmental assumptions above,
  including document overlap and short-session calibration sparsity:
- Decision when projected support or weight stability is inadequate:

The completed SAP must provide justified values and calculations for every
applicable field before confirmatory collection. This template deliberately
does not invent a participant count, precision target, non-inferiority margin,
minimum inclusion probability, maximum weight, or effective-sample-size gate.
Total response rows cannot substitute for independent learners per item.

## Blocking study-design decisions to freeze

- Large-document audit amendment and proof that its sampling frame exists
  before assessment/deck exposure:
- Pretest-interference evidence or randomized/order/carryover design that
  explicitly accounts for interference:
- Meaning prompt, hidden target-sense/context mapping, ambiguity status, and
  bilingual adjudication rubric version:
- Human theta-interval endpoint decision and independent latent reference, if
  literal human theta coverage is retained:
- Confirmation that developmental interference/rubric work cannot enter the
  untouched confirmatory population:

## Dependence and uncertainty to freeze

- Participant clustering structure:
- Opaque study-document clustering structure:
- Repeated-item and delayed-retest dependence:
- Variance and confidence/credible interval construction:
- Finite-population corrections, if any:
- Small-sample adjustments:
- Inter-rater agreement and adjudication uncertainty treatment:

The approved SAP must select the interval method. This template does not choose
bootstrap, sandwich, design-based, Bayesian, or another construction.

## Outcomes, gates, and multiplicity to freeze

- Primary and secondary outcomes:
- Calibration, deck, realized lexical-coverage, burden, and retention metrics:
- Numerical confirmatory acceptance gates:
- Subgroup analyses and minimum support:
- Multiplicity family/families and control procedure:
- Model comparison and non-inferiority margins:
- Human theta-interval coverage: synthetic-only, independently anchored, jointly
  modeled with reference uncertainty, or omitted from confirmatory human claims:
- Rules for exploratory comprehension outcomes:

Lexical coverage must remain distinct from comprehension. Any comprehension
measure is a separate exploratory or separately powered outcome.

## Missing data and deviations to freeze

- Missing criterion/rater/adjudication labels:
- Abandoned assessments and failed definition lookups:
- Missing delayed retests:
- Protocol deviations and exclusion timing:
- Sensitivity analyses:
- Rules for unexpected data-quality problems:

## Holdout and reproducibility controls

- Participant-disjoint split verification:
- Opaque-document-disjoint split verification:
- Confirmatory holdout access controls:
- Development-seed and frozen-holdout separation:
- Software/toolchain versions and deterministic seeds:
- Dataset, code, and output checksums:
- Amendment procedure and disclosure format:

Estimator, interval, population, or gate choices must not be changed after
confirmatory outcomes are inspected to improve the observed result. Any
necessary post-freeze amendment must be timestamped, justified without reference
to outcome direction, independently approved, and reported with the original
analysis.

## Approval decision

- [ ] The estimands and analysis populations are frozen.
- [ ] Sampling weights and inclusion-probability treatment are frozen.
- [ ] Sample-size, support, attrition, design-weight, effective-sample-size, and
      precision calculations are reviewed and frozen.
- [ ] Large-document sampling, pretest interference, target-sense/ambiguity, and
      human-theta endpoint decisions are approved.
- [ ] Participant/document clustering and the variance/interval method are frozen.
- [ ] Missing-data and multiplicity policies are frozen.
- [ ] Outcomes and confirmatory gates are frozen.
- [ ] Confirmatory outcomes have not been inspected.
- [ ] The participant/document holdout and access process are approved.
- [ ] Confirmatory data collection is authorized to begin.

Until every applicable item is approved, the consented dataset and validator
may be used only for schema rehearsals or explicitly labeled pilot/development
work—not confirmatory claims.
