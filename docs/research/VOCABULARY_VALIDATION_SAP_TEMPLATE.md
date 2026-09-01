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
- [ ] Participant/document clustering and the variance/interval method are frozen.
- [ ] Missing-data and multiplicity policies are frozen.
- [ ] Outcomes and confirmatory gates are frozen.
- [ ] Confirmatory outcomes have not been inspected.
- [ ] The participant/document holdout and access process are approved.
- [ ] Confirmatory data collection is authorized to begin.

Until every applicable item is approved, the consented dataset and validator
may be used only for schema rehearsals or explicitly labeled pilot/development
work—not confirmatory claims.
