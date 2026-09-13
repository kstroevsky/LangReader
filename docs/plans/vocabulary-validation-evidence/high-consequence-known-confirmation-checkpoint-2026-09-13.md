# High-consequence known confirmation checkpoint — 2026-09-13

## Decision

Reject `high-consequence-known-double-confirmation-v1`. Keep production
unchanged and do not tune its occurrence eligibility or response semantics from
this consumed result.

## Frozen execution

The reservation was committed before implementation. The single 1,024-row run
used fresh seed `20260914` from clean source revision `edf5106`. It retained
1,013 eligible and 11 naturally ineligible histories. The selected 11 forensic
cases were not used as the acceptance set.

The candidate leaves the natural production question path, posterior, theta,
stopping, warm weight, and deck intact. It asks a post-path confirmation only
for known-supporting answers whose single occurrence mass exceeds the entire 2%
miss budget. An independent occasion-1 arm is an optimistic bound; a fully
correlated arm repeats the original evidence as a negative control.

## Results

| Arm | Mean warm-cold coverage | Worst warm-cold coverage | Material tails | Mean question reduction |
| --- | ---: | ---: | ---: | ---: |
| Production | -0.1176 pp | -15.0491 pp | 40 | 72.503% |
| Independent confirmation | +0.0466 pp | -4.2226 pp | 32 | 62.596% |
| Fully correlated control | -0.1176 pp | -15.0491 pp | 40 | 62.596% |

The optimistic independent arm eliminated eight material tails and introduced
none, but failed the predeclared zero-tail rule. It requested 5.350 confirmations
on average (median 5, p95 9, maximum 11) and did not exceed the 80-question
ceiling. It added 31 truly unknown cards (12,017 occurrence mass) and 274 truly
known cards (116,304 occurrence mass). No UX cost threshold was invented, but
the imbalance is material adverse precision/burden evidence.

The fully correlated arm changed no deck or coverage result, as required. Thus
the apparent benefit depends on response independence that has not been
demonstrated for real learners.

## Evidence boundary

The candidate fails even under the optimistic arm and is rejected. A passing
synthetic result would still have required human repeat-response correlation,
burden, coverage, and precision evidence. Development-confirmation and release
holdout remain untouched, and production stays on the existing assessment and
deck behavior.

- [Frozen/consumed manifest](high-consequence-known-confirmation-manifest-v1.json)
- [Semantic report](high-consequence-known-confirmation-report-v1.json)
- [Decision analysis](high-consequence-known-confirmation-analysis-v1.md)
- [Raw timings](high-consequence-known-confirmation-timing-v1.json)
