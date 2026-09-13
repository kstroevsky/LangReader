# Warm question-path forensic manifest v1

Status: **frozen, not executed**.

This is a deliberately biased mechanism study, not another candidate policy.
It selects every eligible run in the consumed 1,024-row development report with
a production natural warm-minus-cold coverage loss worse than five percentage
points, then adds `learner-0` from each represented scenario as a deterministic
comparison regardless of that control's outcome. The resulting 11 run IDs are
sealed in the JSON manifest.

The rerun must retain question-level traces for cold/warm natural and 60-question
fixed-budget paths. Each row records the exact question identity, occurrence
mass, difficulty prior, hidden truth, simulated evidence, selection type,
validation state, pre-answer probability, and final item disposition.

The analysis must conserve assessable and missed occurrence mass while reporting:

- the first natural-path question divergence;
- cold-only and warm-only asked mass by hidden truth;
- missed unknown mass partitioned by asked/unasked status and observed evidence;
- known-supporting evidence assigned to truly unknown occurrence mass; and
- final-deck symmetric-difference occurrence mass.

The frozen hypotheses distinguish path divergence, erroneous known-supporting
evidence, never-asked omissions, and scenario-specific mechanisms. Supported
and falsified mechanisms must both be retained.

No result from this selected case set estimates a population failure rate or a
mitigation effect. It cannot authorize a production change, select a threshold,
bind development-confirmation, access the release holdout, reuse consumed POS
held-out data, inspect private GUI fixtures, or touch a user database.
