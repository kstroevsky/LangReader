# Vocabulary assessment next-word optimization — 2026-08-31

## Contract

The user-visible problem is the pause labeled **Updating the estimate…** after
an assessment answer. The production optimization is required to preserve the
full 512-sample model, posterior mathematics, question choice, stopping rules,
and final deck. No lower sample count, approximate loss, or relaxed quality gate
is accepted.

The primary workload is the existing optimized 10,000-lemma benchmark. Because
the development Mac is weak and wall time varies substantially with host state,
the decision also uses retired instructions, cycles, memory, and deterministic
operation counts. The raw A/B reports and `/usr/bin/time -lp` output are retained
beside this document.

## Phase attribution

The baseline phase benchmark attributes most next-card latency to
`assessment.record`: 10,000-lemma state-update p95 was 165–172 ms while the
subsequent `nextQuestion` call was 21–45 ms. Source inspection and the earlier
failed staged candidate identify full posterior-predictive coverage work as the
dominant repeated phase.

## Retained exact optimization

The 512 stratified theta sample indexes are sorted and repeat after the posterior
narrows. The old loop recalculated the same candidate probability for every
sample. The retained implementation calculates it once per distinct theta index
and reuses the identical `Double` value while preserving every random draw and
mask update.

For 10,000 lemmas:

| Profile | Median/max distinct theta indexes | Probability evaluations before | Median after | Reduction |
|---|---:|---:|---:|---:|
| Cold coverage | 36.5 / 58 | 5,120,000 | 365,000 | 92.9% |
| Warm coverage | 28.5 / 34 | 5,120,000 | 285,000 | 94.4% |

An explicit configuration switch recomputes every probability for the baseline.
A deterministic Core test runs both paths through identical answers and requires
the complete `VocabularyAssessmentResult`—including masks, probabilities,
questions, stopping, and deck—to be exactly equal.

### Same-executable A/B

| Metric | Recompute every sample | Reuse repeats | Change |
|---|---:|---:|---:|
| Instructions retired | 109,228,306,118 | 104,442,337,471 | −4.38% |
| Cycles elapsed | 40,443,818,478 | 39,856,806,417 | −1.45% |
| Maximum resident set | 99,483,648 B | 94,830,592 B | −4.68% |
| Peak footprint | 26,134,336 B | 27,510,528 B | +5.27% |
| Cold coverage p95 | 179.72 ms | 180.86 ms | +0.63% |
| Warm coverage p95 | 193.58 ms | 181.47 ms | −6.26% |
| Warm state-update p95 | 177.21 ms | 166.07 ms | −6.29% |

Direction is supported by deterministic work and instruction counts. Wall-time
materiality is mixed for cold readers and positive for warm readers. The change
is retained because it is small, exact, reduces work on every full coverage
update, and adds no unbounded cache. The modest peak-footprint difference is
within run noise and no long-lived storage was added.

## Latency hiding without model changes

Two scheduling changes reduce perceived waiting while keeping exact computation:

- `Not sure` and `I don’t know` reveal the already-prefetched learning content
  immediately. The exact assessment update runs in the background while the
  learner reads; pressing Continue waits only for residual work.
- After `I know it` reveals a definition, LeafReader precomputes the exact
  verified-known branch. It is not applied until the user confirms. A partial or
  incorrect confirmation discards it and runs the correct branch normally.

Stale request IDs, Document Session identity, reset, and cancellation guards
remain authoritative. Tests prove that unknown evidence is not counted before
the background update completes, immediate learning content remains visible,
early Continue waits for the exact result, and a prepared known branch applies
only after verification.

## Rejected exact experiments

- **Contiguous response matrix:** debug tests became faster, but optimized
  coverage p95 regressed. Reverted.
- **Fused known/unknown loss pass:** response-curve reads fell, but retired
  instructions increased from about 107.1B to 114.2B (+6.7%) and CPU work rose.
  Reverted.
- **128-sample staged stopping:** passed latency but failed the frozen quality
  holdout. It remains diagnostic-only and is not part of this optimization.

These results are implementation/performance evidence, not learner calibration.
