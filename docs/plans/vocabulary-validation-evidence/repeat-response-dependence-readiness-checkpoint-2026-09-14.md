# Repeat-response dependence readiness checkpoint — 2026-09-14

## Outcome

The same-session repeat-response study is executable at the protocol and
schedule-schema level, but real collection remains blocked. No human response,
transition estimate, correlation, sample-size claim, prompt wording, distractor
count, delay, or production decision was generated.

The primary estimand is:

`p_persist = Pr(E2 supports known | E1 supports known, K = unknown, protocol)`.

Baseline `K` comes from two-rater adjudication of the first unaided meaning
response sealed before reveal; self-verification never defines truth. `E1` is
the first post-definition self-verification, and `E2` is the repeated
same-session confirmation after the frozen distractor schedule. The analysis
must also retain the complete E1-by-E2 transition matrix conditional on `K`.

The protocol explicitly acknowledges that the first reveal may teach, cue, or
reinforce the response. It therefore estimates dependence under one operational
confirmation protocol and cannot be generalized to different prompts or delays.
Neither prior synthetic arm is treated as a human estimate.

## Fabricated schedule rehearsal

The deterministic package contains 24 unique opaque participant-document-item
records across four fabricated participants, four fabricated documents, and
English/German. Each record preserves the five-event order:

1. first product-style response;
2. seal for blinded scoring;
3. definition and `E1`;
4. distractor block; and
5. repeated confirmation `E2`.

The fixture contains no response, `K`, `E1`, `E2`, outcome, definition, target
context, document text/title/path, or real identity. Prompt, definition,
distractor, and delay fields remain null and every schedule row remains marked
blocked. Negative controls reject event reordering, outcome leakage, and an
invented distractor count.

Fixture SHA-256:
`3c1ce29af18c799378b56e8cab8f98d45113f672c39a59f95422c7708b9c4527`.

- [Blocked protocol](repeat-response-dependence-protocol-v1.md)
- [Fabricated schedule](repeat-response-dependence-fabricated-schedule-v1.json)

## Remaining blockers

Before real developmental collection, review must freeze the exact confirmation
prompt and definition presentation, distractor count and maximum delay,
estimator/interval/confidence method, primary-denominator precision and support,
sample size/attrition, missing-data rule, consent, retention/deletion operations,
and named approval revision.

Production confirmation remains rejected. Development-confirmation and release
holdout remain untouched. The next useful action is external statistical,
research, and consent review of these open fields—not another simulator policy.
