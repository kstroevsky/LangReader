# Longitudinal replication checkpoint — 2026-09-12

## Status

The unchanged 16-scenario real-store longitudinal diagnostic was replicated at
32 learners per scenario. All 512 rows are retained. This is substantially
stronger development evidence than v1's one learner per scenario, but it does
not support the canonical two-percentage-point non-inferiority decision or a
human warm-benefit claim.

## Frozen design

Manifest v2 was committed at `eeaf3579245f35df8a9624b6fd13a99293b77d5c`
before execution. It preserves the v1 mechanisms, three history documents, 60
lemmas, natural/fixed/replay paths, isolated real SQLite stores, 4,096-world
B1/B2 diagnostics, and all eligibility/failure scenarios. The precision plan
declares descriptive/large-effect use only: even an optimistic unclustered
binomial calculation has a worst-case 17.33-point half-width per 32-reader
scenario and 5.48 points across planned eligible comparisons.

## Results

- 512 rows retained; 319 eligible warm runs and 193 ineligible controls.
- Mean natural question reduction among eligible runs: 72.358%.
- Mean warm-minus-cold realized projected coverage: -0.2703 percentage points.
- 150 of 319 eligible runs had an adverse natural coverage difference.
- Worst eligible difference: -13.7616 points in biased self-verification; noisy
  history also reached -13.1247 points.
- Scenario mean differences ranged from +1.0864 points for biased
  self-verification to -0.9133 points for changed difficulty distribution.
- One stable-overlap learner used an eligible stored prior but did not satisfy
  the current-document validation condition, so production correctly retained
  the 20-question minimum. The validator was corrected to accept only the
  canonical conditional minima (8 after validation, otherwise 20) and still
  requires the path to reach its reported minimum.

The positive pooled mean question reduction and small pooled mean coverage
change conceal material tail failures. The result therefore strengthens the
case for scenario/tail reporting and does not establish warm non-inferiority.

## Verification and artifacts

- `validate_vocabulary_longitudinal_report.py ... --self-test` passed after the
  conditional-minimum correction.
- The report preserves store contribution/idempotency/reopen evidence, paired
  truth/response fingerprints, natural/fixed/replay paths, and all adverse/null
  rows.
- [Manifest](longitudinal-development-manifest-v2.json)
- [Semantic JSON](longitudinal-development-report-v2.json)
- [Concise report](longitudinal-development-report-v2.md)
- [Raw timings](longitudinal-development-timing-v2.json)

## Next action

Do not add scenarios or tune production from pooled averages. Diagnose the two
large negative-tail families on development data, predeclare a tail-sensitive
decision rule, and require a new frozen development run before binding the
already sealed development-confirmation reservation to a candidate.
