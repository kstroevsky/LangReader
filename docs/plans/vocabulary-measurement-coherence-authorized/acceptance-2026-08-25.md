# Canonical-roadmap acceptance

Date: 2026-08-25

The user accepts candidate SHA-256 `b218edcb4deff49af2e899553e196d562aa2de0e1a004e49b81bee134ba67512` as the canonical implementation roadmap for the next LangReader vocabulary-measurement phase.

## Accepted verification basis

- Byte-for-byte lineage reconstruction: PASS.
- Requirement ledger: 42 active, 12 deferred, 0 superseded.
- Mechanical verification: PASS with 0 errors and 0 warnings.
- Independent semantic verification: PASS.
- Only `EVID-002`, `VALID-001`, `CAL-001`, and `STUDY-002` changed under the explicit authorization; every unmentioned requirement remains `NO_CHANGE`.

## Canonical amendments

1. **Observation model.** `εknowledge` and evidence-specific `ρ` parameters are independent. Tail-validation contradictions update only `εknowledge`. Evidence-specific coefficients remain independent, versioned cold-start assumptions until criterion-based calibration. Runtime reconstruction and the offline fitter use the same Core observation likelihood and must not maintain separate formulas.
2. **Confirmatory statistics.** The roadmap deliberately does not choose a weighting estimator or interval/variance method. Those choices must be frozen in a separately reviewed Statistical Analysis Plan before confirmatory data collection and before confirmatory outcomes are inspected.

## Canonical ordering and blockers

Implementation first establishes measurement coherence and release validity, then warm/performance robustness and validated predictors/UX. Deferred expansions such as multi-word units, same-POS sense splitting, and an outer empirical risk-control layer remain later work subject to their gates.

The failing version-3 holdout and existing performance evidence remain blockers. Their gates must not be relaxed merely to permit rollout.

## Provenance and change control

The prior candidate SHA-256 `1283794cae1af72d36249ad999fd52fd20f81e07f3b2df2145d31e3033de8ec3` remains failed provenance only and is not canonical. This acceptance does not retroactively validate it.

Future implementation is evaluated against the accepted candidate hash and target requirement ledger. Any semantic deviation from an active requirement requires a new explicit authorization delta; it must not be introduced as implementation judgment.

This acceptance changes canonical plan status only. It authorizes implementation but does not itself change application code.
