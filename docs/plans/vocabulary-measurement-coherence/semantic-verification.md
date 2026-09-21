# Semantic verification report — final repair cycle

## Inputs

- Base plan SHA-256: `868106f57e1fa78a0b0f03c3e4e0dd29d6161500ef6b8ed8d13bc05bcc6a1671`
- Review SHA-256: `f5299abc0c32aa5fb1af34068aaad74e069d08bb274c455f737e06de2379bc5c`
- Independent-attempt-1 candidate: `ba734ee8ea40337735584a7c93a52b4e5233f6305eb2f87bf474e8cada752e1b` — FAIL
- Independent-attempt-2 candidate: `eca0f48d81de2cbdf629e2733a583a52518b5cd575338d4a25b92cf2f921f22a` — FAIL
- Current candidate: `1283794cae1af72d36249ad999fd52fd20f81e07f3b2df2145d31e3033de8ec3`
- Original delta items: 20
- First repair findings: 6
- Second repair findings: 5
- Base ledger: 30 active, 4 deferred
- Target ledger: 42 active, 12 deferred, 0 superseded

The current candidate was rebuilt from the locked base by applying `original-delta.patch` and then `bounded-repairs.patch`. The two independent verifier reports remain represented by `repair-delta.json` and `repair-delta-attempt2.json`; the first failed candidate is preserved under `attempt1/`.

## Final repair-cycle checks

- `VF-01` — **PASS:** hierarchical features fit on training participants/documents, tune on validation participants/documents, and evaluate on the untouched participant-and-document holdout.
- `VF-02` — **PASS:** the unchanged latent and observation functions cite exact Core symbols in `AdaptiveVocabularyAssessment.swift` at immutable SHA-256 `5ff417329db82f4ad655e444927f51adaa07f7d79b674121a028107a9b990166`. A hash mismatch fails closed and requires rebaselining.
- `VF-03` — **PASS:** “evaluate once” and “freeze numerical product gates” were removed; the review-supplied untouched confirmatory holdout remains.
- `VF-04` — **PASS:** preregistration/bounded combinations, expanded exact parity fields, per-mode freeze obligations, and invented MWU implementation contracts were removed.
- `VF-05` — **PASS:** PRIOR-004 records that elapsed-time convolution occurs before the existing 90%/10% mixture.

## Delta pass

**PASS.** Every `F-01` through `F-20` item remains mapped exactly once. Repairs modify only IDs cited by the independent findings. No new production modeling dimension is enabled.

## Preservation and exact-contract pass

**PASS.** Mechanical verification reports no unauthorized ledger changes. The candidate retains the exact evidence coefficients; classification thresholds; Beta(1,19) procedure and 0.05–0.25 clamp; difficulty formulas; 121-point grid; 512 predictive samples; fifth percentile; 16-item shortlist; POS thresholds; version-3 migration; 90%/10% warm mixture and 0.35 smoothing; 180-day/two-session/40-answer/two-validation eligibility; domain gates; export exclusions; 100-learner/0.35-SE/0.01-2PL gates; synthetic quality gates; 150 ms and 16 ms performance gates; commit order; and final commands.

The cold-mode objective is the review-supplied division `expected reduction in decision loss / (λ × question cost)`, not subtraction.

## Negative-control pass

**PASS.** Automatic upload, response telemetry, domain blending, unreviewed empirical packs, 2PL, L1-conditioned difficulty, MWUs, same-POS sense splitting, empirical risk calibration, additional coverage targets, burden modes, and 1024 production samples remain disabled or deferred. Release/benchmark gates remain unchanged and failed evidence remains frozen.

## Cross-interface pass

**PASS.**

1. Tail validation → `εknowledge` → hash-locked unchanged latent function.
2. Independent criterion data → evidence reliability version → Core-owned observation-model artifact.
3. Core observation model → runtime posterior/answered probability plus generated manifest/golden fixtures → fitter.
4. Frozen calibration assignment design → approved reconstructable schema → research records → calibration analysis; activation fails closed until complete.
5. Consented criterion/rater/audit records → separate study dataset → participant-and-document holdout.
6. Training/validation fit and tuning → untouched participant-and-document holdout evaluation.
7. Proper DIF → reviewed item eligibility or deferred L1 residual → subgroup gates.
8. Frozen drift → 121-grid convolution → 90%/10% mixture → warm non-inferiority.
9. Cheap update → optional 128 screen → full 512 candidate-stop/final computation → accepted release-decision tolerance.
10. Separately approved MWU design/validation → MWU production → book-local sense proposals.

## Standalone pass

**PASS.** Exact behavior that must be preserved but was not reproduced in the review is cited by immutable path, symbols, and source hash. The complete PR-body replacement is an adjacent artifact cited by its own SHA-256. Procedures that require future design choices fail closed instead of inventing values or schema fields.

## Disposition

Mechanical verification: **PASS**.

Semantic verification by the primary reviser passed, but final independent verification **FAILED** on recurring `FINAL-001`/`FINAL-002` findings. The revision is **INCOMPLETE** and no further repair is permitted without new source evidence or explicit user authorization. See `independent-verification-final.md`.
