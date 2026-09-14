# Vocabulary realized tail-risk acceptance semantics v1

Status: **definitions frozen; release decision blocked**.

This additive contract distinguishes the production posterior-predictive claim
from a release claim about realized severe misses. It does not change the CAT,
the canonical `EVAL-001` gates, the SAP's approval status, or deferred
`RISK-001` empirical risk calibration.

## Two different claims

Production continues to use:

`Q_0.05(C | E) >= 0.98`.

Under the fitted model and evidence, this means approximately 95% of
posterior-predictive coverage worlds meet 0.98. It does not promise that rare,
high-consequence realized evidence errors cannot produce a much lower coverage
outcome.

Realized tail risk is evaluated on the learner-document assessment unit using
independently scored criterion data and the approved sampling estimator. Define:

`L = max(0, 0.98 - C_realized)`.

For a separately approved severe-coverage threshold `c_severe`, report:

- severe-miss frequency:
  `P_severe(c_severe) = Pr(C_realized < c_severe)`;
- conditional severe expected shortfall:
  `ES_severe(c_severe) = E[L | C_realized < c_severe]`; and
- unconditional mean shortfall: `E[L]` as a frequency-severity guardrail.

Worst observed shortfall remains descriptive because it depends strongly on
sample size. If no severe event is observed, conditional expected shortfall is
not estimable and severe risk is not declared zero; report event support and a
one-sided upper uncertainty bound using the approved method.

The existing `0.96` boundary is retained only as an illustrative development
reference derived from the current two-percentage-point materiality rule. It is
not silently promoted to a release threshold.

## Human and warm-comparison contract

Human estimates must use the approved criterion-audit inclusion weights and
account for participant, opaque-document, and applicable repeated-item
dependence. Report support by language, genre, format, and cold/warm condition.
Missing, criterion-ambiguous, abandoned, failed-lookup, and protocol-deviation
states remain visible; raw row count cannot replace independent support.

Warm comparisons report paired contrasts for severe-miss rate, conditional
severe expected shortfall, unconditional mean shortfall, and question burden.
Pooled mean coverage alone cannot establish tail safety.

## Unresolved release decisions

The following fields are deliberately unapproved and remain `null` in the
machine-readable contract:

- whether release requires frequency, severity, or both;
- the release severe-coverage threshold;
- tolerated severe-miss frequency;
- tolerated conditional and unconditional shortfall;
- estimator, interval construction, and confidence level;
- tail non-inferiority margins and multiplicity rule; and
- named approvers and approval revision.

Choosing those values is a material release/statistical decision. They must be
filled before another safeguard receives an acceptance run and before the
sealed development-confirmation reservation is bound. No synthetic result may
be used to back-solve them.

## Evidence and preservation boundary

Synthetic development remains suitable for mechanism diagnosis and
candidate-specific screens. Prior zero-material-tail rules remain valid for
their frozen candidates but do not become retrospective release semantics.
Development-confirmation stays one-time and untouched; the release holdout
stays last; real-learner held-out evidence is required for human tail claims.

`RISK-001` remains deferred and production empirical risk calibration remains
disabled. The current production warm policy is unchanged.
