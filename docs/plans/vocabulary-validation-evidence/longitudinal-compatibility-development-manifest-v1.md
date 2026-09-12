# Longitudinal current-document compatibility development manifest v1

Status: **frozen, not executed**.

The realized replay evidence shows that most material warm tails implicate early
stopping, while two biased-self-verification tails retain question-path and
prior sensitivity at a common budget. This manifest reserves one bounded
development test of a stricter current-document compatibility condition. It
does not change production behavior.

## Candidate signal

For the two existing warm validation questions at ordinals 4 and 8, calculate
the observed categorical-evidence likelihood under:

1. the warm prefix posterior used by the diagnostic path; and
2. a cold posterior reconstructed from the identical preceding question and
   evidence order.

The cumulative signal is:

`Σ log P(evidence | warm prefix) - Σ log P(evidence | cold prefix)`.

The candidate permits the eight-question minimum only when both validation
answers are non-excluded and the cumulative value is at least zero. Otherwise
the eligible warm prior remains in use, but the diagnostic path must reach the
ordinary 20-question minimum before normal stopping rules apply. This isolates
a minimum-relaxation policy; it does not alter the 0.90 warm weight, question
objective, observation model, or deck selector.

Because the questions were selected under the warm path, the comparison is a
conditional compatibility signal, not an unconditional Bayes factor or proof
that the prior is correct.

## Frozen workload and decision

The fresh seed covers eight eligible-history mechanisms with 128 learners each
(1,024 planned eligible rows), retaining every row. With zero observed material
events, the simple one-sided 95% binomial upper bound is about 0.292% overall
and 2.313% within one scenario; these synthetic independence bounds are not
real-learner evidence.

The candidate passes this development screen only if:

- no warm-minus-cold realized coverage loss is worse than two percentage
  points;
- mean warm-minus-cold realized coverage is at least -0.5 percentage points;
- mean question reduction remains at least 50%; and
- no outcome-dependent threshold tuning occurs.

A failure is retained and consumes this reservation. Testing another signal or
threshold requires a newly frozen development experiment.

## Access boundary

This run must not inspect or bind the sealed development-confirmation set,
access the failed release holdout, reuse consumed POS held-out data, or activate
any production policy. `outcomes` and `consumedAtRevision` remain null until the
single planned execution.
