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

## Real-assessment attribution and exact critical-path revision — 2026-09-01

The retained local `notice` telemetry from a real 9,566-lemma assessment showed
that the synthetic phase attribution above was incomplete for the debug app the
learner was running:

- inventory build: 3,929 ms once;
- assessment initialization: 1,354 ms once;
- questions 1–8: usually 332–464 ms per prepared/update branch;
- after octile calibration ended: repeated 6.9–18.1 second advances while
  selecting adaptive questions 9 and later.

The long transition begins before coverage stopping is eligible at question 20,
so it cannot be caused by posterior-predictive coverage. It is the exact
book-wide expected-loss scorer: up to 16 candidates × two hypothetical
posteriors × 10,000 items × 121 theta points, or about 38.7 million multiply/add
terms per adaptive selection.

### Retained exact question scorer

The scorer now uses the observation likelihood's exact affine form and a
posterior-weighted item/question cross moment. One cross-moment pass supplies
both hypothetical evidence branches, reducing the dominant dot-product terms
from about 38.7 million to 19.4 million per 10,000-lemma selection. The old
scalar implementation remains selectable in the same executable. A Core test
compares every selected question and expected-loss score through 24 answers,
including validation items, and requires matching final selections and
predictive masks.

Current same-executable Release evidence:

| 10,000-lemma profile | Scalar reference p95 | Cross moment p95 | Change |
|---|---:|---:|---:|
| all-unknown answer-to-next | 98.06 ms | 14.75 ms | −85.0% |
| coverage answer-to-next | 151.19 ms | 20.94 ms | −86.1% |
| coverage next-question phase | 75.12 ms | 9.56 ms | −87.3% |

The raw paired reports are
`vocabulary-assessment-cross-moment-{enabled,disabled}.json`. Absolute wall
times moved substantially between host runs, but every paired run favored the
cross-moment path; the deterministic arithmetic reduction is 50% for the
dominant hypothetical item/theta dot products.

The optimized production configuration passes the existing 150 ms Release gate
for all 10,000-lemma cold and warm cases on this machine. Debug Core evidence
also moved materially: the 80-answer limit test fell from 11.57 seconds before
this slice to 2.91 seconds, while exact repeated-theta parity fell from 5.27 to
1.27 seconds.

### Deferred exact coverage stopping

Coverage mode still uses all 512 samples. When the previous stable-deck streak
is zero or one, the current answer cannot mathematically produce the required
third stable result. LeafReader therefore computes the exact next question
first, publishes it, and runs the independent exact coverage/deck calculation
in a background task. That result is merged before another answer may mutate
the assessment. If the prior streak is already two, the exact synchronous
barrier remains because that answer can terminate the assessment.

A deterministic Core test runs synchronous and deferred assessments side by
side and requires identical next questions, stopping, probabilities, masks, and
final deck. The app disables the newly visible question's answer controls only
for any residual background interval, and Continue waits for residual work
rather than accepting a second mutation early.

### Additional retained exact work reductions

- Posterior updates multiply only the new answer's 121 likelihoods when
  `epsilonKnowledge` is unchanged. A full replay remains mandatory after a
  validation contradiction changes `epsilonKnowledge`. At answer 20 this
  removes 95% of replay likelihood operations; at answer 80 it removes 98.75%.
- Target-coverage selection no longer builds an unused 10,000-entry probability
  dictionary.
- Current expected loss reuses the already cached item probabilities.
- Predictive sampling uses candidate-indexed evidence rather than 10,000 string
  dictionary lookups and iterates sorted theta runs rather than performing 5.12
  million repeated-index comparisons.
- Worst-tail ranking builds an eight-word mask once and uses exact popcounts,
  replacing roughly 260,000 arbitrary sample lookups with 80,000 contiguous
  word operations for the 10,000 × 512 workload.

### Rejected platform acceleration

Two Accelerate layouts were measured and removed. Repeated narrow matrix-vector
calls and one batched vDSP/BLAS matrix multiplication both measured around
240–282 ms p95 for 10,000-lemma all-unknown selection, versus 14.75 ms for the
retained scalar cross-moment implementation. Neither platform abstraction nor
its extra response-matrix copy remains in production.
