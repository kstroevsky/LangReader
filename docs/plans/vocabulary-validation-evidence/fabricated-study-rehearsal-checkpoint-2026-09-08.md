# Fabricated study-package rehearsal checkpoint

Date: 2026-09-08

Base commit: `bb0436685dfa133a30517bc250c33a5d406c1c90`

## Outcome

An additive relational study package schema v2 now supports deterministic fabricated rehearsal without changing or migrating the accepted schema-v1 dataset. V2 hard-codes `dataRole = fabricated-rehearsal`, requires `realCollectionAuthorized = false`, and requires `estimatorStatus = provisional-not-approved`; it therefore cannot be presented as permission to collect or analyze confirmatory participant data.

Core tables separate participants, documents, assessments, full-inventory predictions, criterion/rater rows, question traces, authoritative deck snapshots, sampling manifests, and retest manifests. Mutable deck membership is represented only by an identified snapshot. `criterion-ambiguous` and missing response are distinct study statuses and do not add production evidence categories.

The Core validator checks identifiers, referential integrity, participant/document split agreement, near-duplicate split leakage, full-inventory count and occurrence-mass conservation, finite probabilities, pre-reveal criteria, rater/ambiguity/missingness semantics, question ordering inputs, deck membership, sampling diagnostics, and retest linkage. Schema v1 remains unchanged and continues to pass its original tests.

The existing offline validator now dispatches by schema version. Its v2 path independently rejects private product fields, real-collection mode, split/join failures, missing predictions, changed denominators, post-reveal pre-reading criteria, broken decks, and missing retests.

## Fabricated rehearsal

The generated package contains two pseudonymous fabricated participants, English and German documents, a small-document census and a large-document probability sample, cold/warm assessments, proposed/edited decks, immediate/delayed phases, rater disagreement/adjudication, ambiguity, nonresponse, an abandoned assessment, lookup failure, and deliberately insufficient subgroup/DIF support.

All endpoint inputs are mapped. The small-document census Brier score is `0.041667`, independently checked from `(0.85−1)²`, `(0.20−0)²`, and `(0.75−1)²`. Large-document weighted coverage, warm non-inferiority, DIF, and human theta-interval coverage remain explicitly non-estimable because no estimator, variance method, non-inferiority margin, adequate learner support, or human latent reference has been approved. No default Horvitz–Thompson, Hájek, bootstrap, sandwich, or other method was introduced.

Sampling manifests expose minimum inclusion probability, maximum design weight, weight-based effective sample size, and expected selected-card/final-tail support. These are diagnostics, not acceptance thresholds. The fabricated package contains no raw document text, title/path, context, definition, typed meaning, account identity, or exact product timestamp.

## Verification

- `swift test --filter VocabularyValidationStudyDatasetXCTests` — schema v1 remains green.
- `swift test --filter VocabularyValidationStudyPackageV2XCTests` — 3 v2 tests, 0 failures.
- `python3 scripts/validate_vocabulary_validation_study.py --self-test` — v1 plus v2 validator fixtures and negative controls passed.
- `python3 scripts/run_vocabulary_validation_study_rehearsal.py --self-test` — independent calculation and real-collection negative control passed.
- A second generated package/analysis/Markdown set was byte-identical to the retained artifacts.
- `./scripts/check.sh --no-build` passed: Core portability/ownership, native-reader boundary, strict Swift 6 build, 161 Swift tests with one expected private-fixture skip, 281 logic tests, evaluator suites, and all deterministic validators.

`./scripts/build_app.sh` was not run because this slice changes no app UI, resources, native reader, assembly, or framework linkage. No participant, confirmation, or release-holdout data was accessed.

## Artifacts

- [Fabricated relational package](fabricated-study-package-v2.json) — SHA-256 `60d4874b6b8fc8d2f64e0b2ce868c3b0c6000f274424df4c9cfbcc7418fcc493`
- [Provisional analysis result](fabricated-study-rehearsal-analysis-v1.json) — SHA-256 `1922a525e83e2be8afc685bb34ad58b101c05ab1db968c9aa3a1b6868ab02b25`
- [Concise rehearsal report](fabricated-study-rehearsal-v1.md) — SHA-256 `6972791778d66b3517cda3292f374a6d500b653718eb21a9288a69195128d1cf`

## Remaining decisions

Before any real or confirmatory use, the target-sense/context mapping and bilingual rubric, pretest-interference treatment, consent/privacy contract, sampling estimator, design-weight treatment, clustering/variance method, missingness, multiplicity, human-theta endpoint, warm margin, sample-size support, and analysis populations still require the plan's separate review/freeze process. This fabricated rehearsal does not amend the canonical roadmap or authorize collection.

The next independent implementation slice is licensed POS fixtures and inventory/deck consequence measurement, which can proceed without resolving these human-study decisions.
