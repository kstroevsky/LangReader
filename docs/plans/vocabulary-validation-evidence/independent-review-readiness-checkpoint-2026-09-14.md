# Vocabulary independent-review readiness checkpoint — 2026-09-14

## New refinement

The pretest protocol now requires a decision-relevant equivalence guardrail for
the complete non-exclusion first-stage response distribution. A passing
`I know it` rate endpoint is insufficient by itself.

The guardrail population is `I know it`, `Not sure`, and `I don’t know`.
`Not a word/name` remains a separately reported exclusion action and is not
renormalized into that distribution.

Independent review may choose total-variation distance, predeclared
category-specific margins, or another explicitly reviewed distributional
equivalence formulation. No method, margin, estimator, interval/joint region,
confidence level, multiplicity rule, or minimum cell support is selected. A
failed or inconclusive guardrail keeps confirmatory collection blocked even when
the known-claim primary endpoint passes.

## Complete review packet

The machine-readable checklist now requires seven decisions:

1. practical known-claim equivalence margin and inferential method;
2. complete categorical-distribution guardrail;
3. criterion-`K` acquisition, classification error, rater uncertainty, and
   sensitivity analysis;
4. immutable product UI and evidence-mapping revisions;
5. repeat prompt/definition/distractor/delay and rare-denominator precision;
6. one formal conditional tail-severity endpoint; and
7. sample size, dependence, missingness, consent, retention/deletion, and named
   approval.

For item 6, once `c_severe < 0.98` is fixed:

`conditionalTargetShortfall = (0.98 - c_severe) + conditionalThresholdExcessSeverity`.

The two conditional severity metrics contain the same information up to a known
constant, so both are not silently promoted to separate release endpoints.

## No-outcome rehearsal

The 32-row v3 assignment rehearsal preserves the aligned product actions and
adds explicit null fields for first-stage category, missingness, exclusion, and
known-claim indicator. It retains the unselected guardrail method/margins and a
joint-decision blocked status.

Negative controls reject choosing total variation without review, inserting a
fabricated response category, or downgrading the decision to the primary
endpoint alone.

Fixture SHA-256:
`57dfc4110a13b7936a11035de49a442357a399bfa7ebfdcc43af3e79580e8059`.

- [Pretest protocol v3](pretest-interference-development-protocol-v3.md)
- [Independent-review checklist](independent-review-decision-checklist-v1.md)
- [No-outcome categorical rehearsal](pretest-interference-fabricated-assignment-v3.json)

## Boundary

This is readiness for independent statistical/research/privacy review, not its
completion. Every checklist decision is null and every collection, production,
confirmation, development-confirmation, and release-holdout authorization is
false. CI remains outside this work.
