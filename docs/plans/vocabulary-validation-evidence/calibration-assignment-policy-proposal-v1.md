# Calibration assignment policy proposal v1

## Decision requested

Review the proposed 7.5% calibration-assignment mechanism and its linked study
trace schema. This document is a proposal, not approval. The reserved
`calibration` selection path remains disabled in production, default settings,
diagnostic flags, and fabricated rehearsals.

## Assignment mechanism

At each eligible scored-question ordinal, draw one deterministic study RNG value
and create a calibration opportunity when the value is below 0.075. There is no
minimum quota, maximum quota, or short-session rounding. Therefore an eight-item
warm session can legitimately contain zero calibration assignments; its expected
count is 0.6 rather than a forced 12.5% assignment.

Ordinals 15, 20, 25, and so on remain reserved for tail validation. Calibration
never replaces them. A calibration answer counts inside the existing 8/20/80
question limits and updates the same production observation model; it is marked
with `selectionType = calibration` so analysis can condition on its selection.
Exclusions do not become scored answers. Exhausted pools fall back to ordinary
adaptive selection and retain a `noEligibleCandidates` outcome.

For the participant's pre-question ability bin, the policy chooses the nonempty
predicted-known stratum with the lowest frozen support count, breaking ties by
the declared bin order. It then samples uniformly within that stratum. The
joint item propensity is 0.075 divided by the chosen stratum's candidate count.
This depends on prior responses, posterior state, the remaining candidate pool,
support history, and reserved ordinals; the package makes no ignorability claim.

## Reconstruction and privacy

The trace retains the four canonical fields plus policy version, ability/bin and
pool metadata, support snapshot hashes, eligible/stratum counts, slot and item
draw indexes/values, and conditional/joint probabilities. A restricted pool
snapshot keyed by opaque assessment and snapshot IDs supplies the lexical item
frame needed for offline reconstruction. Product document IDs/titles, paths,
raw text, context, definitions, typed meanings, account identity, and exact
timestamps remain forbidden. Ordinary product research export is unchanged and
nothing is transmitted automatically.

Run the executable reconstruction and negative controls with:

```sh
python3 scripts/validate_vocabulary_calibration_assignment_package.py --self-test
python3 scripts/validate_vocabulary_calibration_assignment_package.py \
  docs/plans/vocabulary-validation-evidence/calibration-assignment-policy-proposal-v1.json \
  docs/plans/vocabulary-validation-evidence/calibration-assignment-reconstruction-fixture-v1.json
```

## Feasibility warning

After preserving tail-validation ordinals, expected calibration counts are 0.6
for 8 scored questions, 1.35 for 20, and 4.95 for 80. Under a deliberately simple
uniform-allocation approximation, the 285-item English supplement would require
about 5,758 eighty-question learner-document sessions to reach 100 independent
learners per item; the 264-item German supplement would require about 5,333.
Thirty learners per item by each of five balanced ability bins would require
about 8,636 and 8,000 sessions respectively. Short sessions are much sparser.

This makes a broad per-document calibration frame implausible without substantial
document overlap. Approval should narrow or reuse a protocol-frozen calibration
bank, or justify the larger support, before collection. The at-least-100-learner,
SE <= 0.35, reviewed-pack, DIF, and 2PL gates are not lowered.

## Exact proposed canonical delta

If separately approved, replace only `CALDATA-001.normative_payload` with:

```json
{
  "slot_rate": 0.075,
  "cadence": "independent Bernoulli at each eligible scored ordinal; no quota or rounding",
  "tail_validation_priority": "ordinals 15, 20, 25, ... remain reserved",
  "question_limit_semantics": "calibration answers count within existing 8/20/80 scored-question limits",
  "ability_bins": [-1.5, -0.5, 0.5, 1.5],
  "candidate_policy": "least-supported nonempty predicted-known bin for current ability bin, then uniform item draw",
  "assignment_probability": "0.075 / chosenStratumCandidateCount conditional on history and eligibility",
  "minimum_selection_fields": ["questionOrdinal", "selectionType", "predictedKnownBeforeAnswer", "thetaBinBeforeAnswer"],
  "additional_schema": "policy/pool/support/RNG/propensity/outcome fields in calibration-assignment-policy-proposal-v1.json",
  "activation_condition": "explicit approval of this versioned policy and privacy/schema contract",
  "production_enabled": false
}
```

All other canonical requirements remain unchanged, including the observation
likelihood, evidence reliabilities, tail cadence, question limits, pack
eligibility, DIF rules, 2PL gate, privacy exclusions, and disabled production
state. Approval must be explicit and must occur before real collection or slot
activation; generated files and elapsed time do not constitute approval.
