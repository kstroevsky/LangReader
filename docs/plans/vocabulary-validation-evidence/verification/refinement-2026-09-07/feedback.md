# Feedback source and closed delta

The user reviewed the prior plan and requested five bounded refinements before implementation:

1. Independent predictive evaluation must distinguish B1 (same deterministic theta strata as production A, independent latent-item draws) and B2 (independently randomized/shifted stratified posterior positions plus independent latent-item draws). Production A remains unchanged; distinguish Bernoulli/mask-bank effects from the broader finite predictive approximation.
2. Add a fresh synthetic development-confirmation seed/document set between freely used diagnostic-development data and frozen release holdout. Do not use it during iterative design. Use it only after a diagnostic/model candidate is frozen, before touching the release holdout.
3. Make pretest interference an explicit blocking decision for confirmatory human collection. Developmental studies may measure it, but confirmation must not proceed until evidence supports the chosen pretest procedure or the study design explicitly accounts for interference.
4. Remove “where feasible” from confirmatory target-sense/rubric freezing. Target-sense/context mapping and scoring rubric must be frozen before confirmatory responses/model outcomes are inspected.
5. Separate core human validity from the broader equal-total-preparation-time product-value comparison. The latter must not automatically block establishing item calibration, deck validity, realized coverage, burden and warm non-inferiority unless an authoritative requirement specifically makes it a release prerequisite.

The same request adds sampling-design diagnostics for minimum inclusion probability, maximum design weight/effective sample size, and expected selected-card/final-tail support. Do not invent numerical thresholds; use them to inform eventual SAP/design freeze.

Preserve authority boundaries, canonical roadmap hashes/counts, production CAT behavior, release gates, frozen holdout, v2 golden, deferred features and PR #9 status. Revise the plan and verification/ledger artifacts losslessly before the first execution milestone.

The requested first milestone is synthetic causal diagnostics: failed-deck forensic records, exact occurrence-mass conservation, independent A/B1/B2 frozen-deck evaluation, reproducibility/RNG-stream controls, fixed-bank and small-enumeration oracle fixtures, and natural/fixed-budget/common-replay infrastructure where directly required. Exclude study-data schema changes, production selector changes, warm-production changes, POS policy changes, calibration slots and release-holdout tuning. Stop at a review checkpoint with changed files, mathematical/statistical invariants, diagnostics-off production parity, deterministic tests, narrow results, overhead, design issues and a longitudinal-warm recommendation.

**Later controlling instruction:** the user said “STOP BEFORE WRITING CODE” and requested detailed instructions for another mode. The current task therefore completes documentation/refinement verification and implementation handoff only. The first milestone remains future execution scope; no code, test, study or release run is claimed here.

F01–F05 map to the numbered refinements, F06 to sampling diagnostics, and F07 to the milestone/checkpoint plus the later stop-before-code instruction. Everything else is NO_CHANGE. `patches.json` retains every exact old/new text replacement. `original-ledger.json` is byte-identical to the prior target ledger; `base-ledger.json` changes only its top-level canonical hash to identify the locked full plan as this revision's base rather than the older initial scope scaffold.
