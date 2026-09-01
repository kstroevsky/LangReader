# Semantic verification report — authorized lineage

## Inputs and lineage

- Locked base plan SHA-256: `868106f57e1fa78a0b0f03c3e4e0dd29d6161500ef6b8ed8d13bc05bcc6a1671`.
- Review SHA-256: `f5299abc0c32aa5fb1af34068aaad74e069d08bb274c455f737e06de2379bc5c`.
- Prior terminally failed candidate SHA-256: `1283794cae1af72d36249ad999fd52fd20f81e07f3b2df2145d31e3033de8ec3`; it remains in `../vocabulary-measurement-coherence/` with its failed disposition.
- New authorization SHA-256: `762b97c9fff039b46f13d235a9e69b0eec1f37e7dcf29c7e7b1d9bf9a46f53f1`.
- Consolidated delta SHA-256: `77de2b1afe7c1c4c33ebe7387ca7473101347e417e560527935e06cbd42b786d` (`F-01` through `F-22`).
- Separate authorization delta SHA-256: `52e0bd344f9ebbc66881f232f106f8879b42f2d3703595706d1aacd1815ae9eb` (`AUTH-001` and `AUTH-002`).
- Candidate SHA-256: `b218edcb4deff49af2e899553e196d562aa2de0e1a004e49b81bee134ba67512`.

The candidate is reproducibly related to the locked base by the retained original and bounded-repair patches, followed by `authorized-amendments.patch`. The authorization patch is exactly the unified diff from the failed candidate to this candidate. The failed candidate is provenance only and is not promoted or retroactively accepted.

## Mechanical pass

**PASS.** `plan_guard.py verify` reports no errors or warnings. It records 42 active requirements, 12 deferred requirements, and 0 superseded requirements. Ten sections changed, four sections were added, and no section was removed; every changed or added section is delta-authorized.

The previous and authorized target ledgers contain identical requirement-ID sets. Exactly four existing records differ between them: `EVID-002`, `VALID-001`, `CAL-001`, and `STUDY-002`. These are exactly the requirements named by `AUTH-001` and `AUTH-002`; all other target-ledger records are unchanged.

## Delta pass

**PASS.** Original feedback items `F-01` through `F-20` remain mapped and mechanically anchored. `F-21` applies `AUTH-001` to the observation-model requirements. `F-22` applies `AUTH-002` to the confirmatory-study requirement. Unmentioned requirements retain `NO_CHANGE` status.

## Authorized mathematical-change pass

**PASS.** The candidate now defines two separately parameterized layers:

1. `P(K_j | θ, b_j, εknowledge)` is the latent-knowledge model. The existing `adjustedProbability`/`baseItemProbability` mathematical form remains hash-locked provenance for this layer.
2. `P(E | K_j, ρE)` is the observation model. The shared `min(reliability, 1 - errorFloor)` cap is explicitly removed from the revised observation likelihood and answered-item reconstruction.

For latent known probability `p`, the candidate gives the full authorized likelihoods:

- known-supporting evidence: `ρE × p + (1 - ρE) × (1 - p)`;
- unknown-supporting evidence: `ρE × (1 - p) + (1 - ρE) × p`.

Tail-validation contradictions update only `εknowledge`. They do not automatically reduce any evidence-specific `ρ`. Independently scored protocol evidence may update the corresponding `ρ` without redefining `εknowledge`. Existing numeric `ρ` values remain versioned cold-start engineering assumptions until independently calibrated.

The Core `VocabularyObservationModel.evidenceLikelihood` is the one normative implementation for runtime posterior updates and answered-item reconstruction. Its generated manifest and golden fixtures are the fitter contract, preventing a second independently authored observation formula.

## Statistical Analysis Plan pass

**PASS.** The candidate preserves the authorized study-design requirements: stratified large-document audits, recorded inclusion probabilities, participant/document clustering, participant-and-document holdouts, delayed retesting, frozen outcomes/gates, and weighted estimation appropriate to the design.

It deliberately does not choose a weighting estimator or variance/interval construction. A separately reviewed SAP must be approved and frozen before confirmatory data collection and before confirmatory outcomes are inspected. The SAP must freeze the estimand, weighting estimator, treatment of inclusion probabilities, clustering structure, variance/interval method, missing-data rules, multiplicity policy where applicable, confirmatory outcomes and gates, and confirmatory analysis populations. Retrospective method selection to improve observed results is prohibited.

## Preservation and exact-contract pass

**PASS.** Outside the four authorization-amended ledger records, the authorized target ledger is byte-equivalent to the terminal candidate's target ledger. The candidate retains the evidence coefficients, probability thresholds, Beta(1,19) procedure and 0.05–0.25 clamp, difficulty-prior formulas, quadrature and posterior-sampling counts, POS thresholds, version-3 migration, warm-prior mixture and eligibility rules, domain and calibration gates, privacy exclusions, synthetic and real-learner evaluation gates, performance gates, staged order, and final verification commands.

## Negative-control pass

**PASS.** No response telemetry or automatic upload is introduced. Domain blending, same-POS sense splitting, empirical parameters, 2PL, L1-conditioned difficulty, and empirically calibrated risk remain inactive until their existing gates pass. The roadmap does not claim synthetic populations represent real humans, does not infer comprehension from lexical coverage, and does not promote the prior failed candidate.

## Cross-interface pass

**PASS.** The principal chains are complete:

1. Tail-validation contradiction → `εknowledge` update → latent-knowledge response curve only.
2. Independently criterion-scored protocol evidence → evidence-specific `ρ` version → Core observation model.
3. Core observation model → runtime posterior/answered probability and generated manifest/goldens → offline fitter parity.
4. Stratified audit design and inclusion probabilities → pre-data approved SAP → frozen weighted confirmatory analysis.
5. Training/validation participants and documents → untouched participant-and-document confirmatory holdout.

## Standalone pass and disposition

**PASS.** The candidate states both newly authorized semantic contracts directly, identifies the immutable authorization and source provenance by hash, and does not rely on the reader to reconcile the prior failed report. Mechanical, primary semantic, and fresh independent forward verification all pass. The artifact is an independently verified candidate; it is not labeled canonical until user acceptance.
