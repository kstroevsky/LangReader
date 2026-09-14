# Vocabulary pretest-interference developmental protocol v3

Status: **categorical-distribution guardrail required; collection blocked**.

This v3 overlay preserves every v2 response-modality, randomization, delayed-
reveal, rater, dependence, privacy, and access contract by checksum. It adds one
decision requirement: equivalence of the `I know it` rate alone is insufficient
to rule out interference in the evidence stream.

The known-claim rate difference remains the primary endpoint:

`Pr(known claim | criterion first) - Pr(known claim | product first)`.

The non-exclusion first-stage distribution over `I know it`, `Not sure`, and
`I don’t know` is now a decision-relevant equivalence guardrail. `Not a
word/name` remains a separately reported exclusion action and is not silently
renormalized into the knowledge-response distribution.

Independent statistical review must choose one guardrail formulation before
collection. Allowed families are:

- total-variation distance,
  `TV = 0.5 * sum_k |P_k(criterion first) - P_k(product first)|`;
- predeclared category-specific equivalence margins; or
- another explicitly reviewed distributional equivalence formulation.

No method or margin is chosen here. Estimator, interval/joint region, confidence
level, multiplicity relation to the primary endpoint, and minimum distributional
cell support also remain null.

Interference equivalence is supported only when both the primary endpoint and
the categorical-distribution guardrail meet their separately approved criteria.
A passing primary with a failed or inconclusive guardrail keeps confirmatory
collection blocked. The guardrail cannot be downgraded to descriptive reporting.

Every assigned item must retain its complete first-stage category. Missing
responses and exclusions remain explicit; the primary analysis cannot silently
condition on observed nonmissing responses. All collection, production, and
holdout authorizations remain false pending independent approval.
