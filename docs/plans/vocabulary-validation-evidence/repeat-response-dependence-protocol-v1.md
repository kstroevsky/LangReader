# Vocabulary repeat-response dependence protocol v1

Status: **design defined; real collection blocked**.

This developmental protocol estimates the missing quantity behind the rejected
double-confirmation safeguard: whether a known-supporting error persists when
the same participant confirms the same lexical item again in the same session.
It does not assume independent responses and does not authorize a production
confirmation feature.

## Operational sequence

For each participant-document-item record:

1. collect and seal the first unaided product-style meaning response before
   definition, context, or correctness feedback;
2. have two blinded raters score that response against the hidden target
   sense/context, with adjudication and separate ambiguity status; this defines
   baseline `K`, not self-verification;
3. show the frozen product definition and collect first self-verification `E1`;
4. present the frozen number of distractor items without further target-item
   feedback; and
5. repeat the frozen confirmation prompt and collect `E2` before further target
   feedback.

The reveal between `E1` and `E2` may teach, cue, or reinforce the participant.
That is part of the operational confirmation protocol, not evidence that the
two responses are independent. Results do not transfer automatically to a
different prompt or delay.

## Estimands

The primary estimand is:

`p_persist = Pr(E2 supports known | E1 supports known, K = unknown, protocol)`.

The derived detection probability is `1 - p_persist`. The analysis must also
retain the full E1-by-E2 transition table conditional on `K`, relevant marginal
error probabilities, and within-item association when estimable. Overall row
count cannot replace the primary denominator of independent participant-item
records with `K = unknown` and known-supporting `E1`.

Participant, opaque-document, and lexical-item dependence must be handled. Full
missingness, ambiguity, abandonment, and protocol-deviation states remain
visible. Conditioning on `E1` cannot be reported without the joint transitions.

## Unresolved decisions and access boundary

The confirmation wording, definition presentation, distractor count, maximum
delay, estimator, interval/confidence method, target precision, required primary
denominator support, sample size/attrition, missing-data rule, consent,
retention/deletion operations, and named approval remain unapproved.

A deterministic 24-record rehearsal may validate schedule/schema behavior but
contains no outcomes. Real participant collection, confirmatory collection,
development-confirmation, release-holdout access, ordinary user-database access,
automatic upload, and production changes remain unauthorized.

Neither the optimistic independent synthetic arm nor the fully correlated
negative control is a human estimate. Production confirmation can be considered
only after `p_persist` and burden are estimated with approved precision under a
protocol matching the proposed product interaction.
