# User authorization — terminal findings FINAL-001 and FINAL-002

The user authorized both amendments exactly for resolving the two terminal verification findings while preserving every other requirement under the existing lossless rules.

## AUTH-001 — observation model mathematical change

Approved contract:

```text
εknowledge ⟂ ρevidence
```

Remove the intended-model coupling:

```swift
min(reliability, 1 - errorFloor)
```

Requirements:

- Tail-validation contradictions update only `εknowledge`.
- `εknowledge` represents residual person-item/model mismatch not explained by the one-dimensional Rasch curve.
- Evidence-specific `ρ` parameters represent measurement reliability of response categories.
- `ρ_verifiedKnown`, `ρ_typedVerifiedKnown`, `ρ_reportedUnknown`, `ρ_unsure`, and the other evidence-specific coefficients remain independent of `εknowledge`.
- Existing versioned numeric values remain cold-start engineering assumptions until independently estimated from the scored validation pilot.
- A tail-validation contradiction must not automatically reduce every future verified response’s assumed reliability.
- Future evidence that a response protocol is noisy updates the corresponding `ρ`, not `εknowledge`.
- `P(Kij = 1 | θi, bj, εknowledge)` models latent knowledge.
- `P(Eij | Kij, ρE)` models the observation process.
- This authorization explicitly supersedes preservation language requiring the current observation likelihood to be extracted without mathematical change. Current source remains implementation provenance, but this particular mathematical contract is authorized to change.

Authorized delta language:

> Authorized mathematical change: replace the shared `errorFloor`/evidence-reliability cap with separate latent-knowledge mismatch and evidence-reliability parameters. Tail-validation contradictions affect only `εknowledge`. Evidence-specific `ρ` coefficients remain versioned independent cold-start assumptions until independently calibrated.

## AUTH-002 — validation-study Statistical Analysis Plan gate

Approved contract:

- The roadmap does not choose the estimator or confidence/uncertainty interval construction.
- A separately reviewed and approved Statistical Analysis Plan (SAP) is frozen before confirmatory data collection.
- The roadmap retains stratified large-document audits, recorded inclusion probabilities, participant/document clustering, participant-and-document holdouts, frozen outcomes/acceptance gates, delayed retesting where specified, and weighted estimation appropriate to the sampling design.
- The roadmap does not select Horvitz–Thompson versus Hájek, bootstrap versus sandwich versus design-based intervals, or another estimator/interval method.
- Before confirmatory collection, the SAP freezes the estimand, weighting estimator, treatment of inclusion probabilities, clustering structure, variance/interval method, missing-data rules, multiplicity policy where applicable, and confirmatory analysis populations.
- The SAP is approved before inspecting confirmatory outcomes. Estimator or interval choices cannot be selected retrospectively to improve observed results.

Authorized delta language:

> Statistical Analysis Plan gate: before confirmatory data collection begins, a separately reviewed and approved SAP must freeze the estimand, weighting estimator, treatment of inclusion probabilities, clustering structure, variance/interval method, missing-data rules, multiplicity policy where applicable, and confirmatory analysis populations. The roadmap deliberately does not select those methods.

## Authorization boundary

The two amendments above are the only new semantic authority. The revision must restart from the locked base and create a new candidate/hash/verification lineage. All other requirements remain governed by the prior delta, verified repairs, and preservation rules unless another contradiction is independently demonstrated. The prior failed candidates remain failed provenance and do not transfer acceptance.
