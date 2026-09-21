# Vocabulary question-objective coherence experiment — 2026-09-07

## Decision contract

The audit identified two distinct semantic questions:

1. whether adaptive classification loss should include answered items or only
   remaining unasked items;
2. whether the two hypothetical branches are a complete Bayesian expectation
   over observable responses.

The experiment must not change the posterior, 512 predictive samples, coverage
deck, deferred exact stopping, or cross-moment arithmetic. Production may adopt
a changed selector only if paired development evidence does not worsen any
coverage-hit rate by more than two percentage points, does not worsen Brier or
ECE by more than 0.01, keeps deck precision at least 0.50, and passes the 150 ms
10,000-lemma Release gate. The frozen release holdout is not used for tuning.

## Precise production semantics

Production uses `allNonExcluded + evidenceSurrogate`.

- Its loss population contains every non-excluded lexical item. This includes
  answered items because direct evidence is intentionally strong but fallible;
  their posterior uncertainty is not forced to zero.
- Its question score is an exact deterministic two-branch decision surrogate:
  latent `P(known)` weights hypothetical `.verifiedKnown` and
  `.reportedUnknown` evidence updates. It is not the full Bayesian expectation
  over all observable response categories.
- The cross-moment implementation is algebraically equivalent to the scalar
  reference for this stated surrogate.

Two experimental configurations are retained behind explicit Core parameters:

- `remainingUnasked + evidenceSurrogate` removes answered items from current
  and hypothetical branch loss.
- `remainingUnasked + latentKnowledgeRisk` branches coherently on latent
  `K=1/K=0`. Both branches remain affine in the question response curve and use
  the same cross-moment engine.

## Controlled synthetic comparison

The development sweep used six version-derived seeds, 32 readers per scenario,
four documents, and 120 lemmas. Paired diagnostic substreams were mandatory.
All three reports contain identical hidden-truth fingerprints, so differences
come from question selection rather than different synthetic people.

### Remaining-unasked versus production

| Scenario/mode | Brier Δ | ECE Δ | Coverage-hit Δ | Precision Δ | Questions Δ |
|---|---:|---:|---:|---:|---:|
| Well-specified / all unknown | +0.0021 | −0.0000 | 0.0 pp | −0.0035 | −1.75 |
| Well-specified / coverage | +0.0003 | +0.0005 | +0.5 pp | −0.0009 | +0.40 |
| Item residual / all unknown | +0.0023 | −0.0005 | 0.0 pp | −0.0030 | −1.90 |
| Item residual / coverage | −0.0002 | +0.0016 | +0.5 pp | +0.0016 | +1.10 |
| Response noise / all unknown | +0.0006 | −0.0012 | 0.0 pp | −0.0015 | −1.60 |
| Response noise / coverage | +0.0004 | −0.0007 | −1.0 pp | −0.0015 | −1.09 |
| Idiosyncratic / all unknown | +0.0018 | −0.0003 | 0.0 pp | −0.0036 | −1.58 |
| Idiosyncratic / coverage | +0.0008 | +0.0008 | **−2.6 pp** | −0.0025 | −0.19 |

The experiment saves about 1.6–1.9 questions in all-unknown mode, but its
idiosyncratic coverage-hit regression exceeds the predeclared two-point limit.
It is not promoted to production.

### Latent-state risk versus remaining-unasked surrogate

Most changes are small or mixed. Item-residual coverage hit improves 1.0 point
and response-noise/well-specified coverage hit is unchanged, but idiosyncratic
coverage hit loses another **2.1 points**. Relative to production, the combined
idiosyncratic regression is therefore about 4.7 points. The latent-state
objective remains experimental until real response-category probabilities and
independent validation justify a full multi-response Bayes-risk selector.

These are synthetic robustness results, not human calibration evidence.

## Performance

All three configurations keep the exact cross-moment engine and passed the
10,000-lemma Release gate in the retained run:

| Configuration | Cold all-unknown p95 | Cold coverage p95 | Warm coverage p95 |
|---|---:|---:|---:|
| Production | 13.66 ms | 19.64 ms | 22.40 ms |
| Remaining-unasked surrogate | 38.89 ms | 147.04 ms | 110.71 ms |
| Latent-state risk | 60.62 ms | 101.51 ms | 110.12 ms |

Absolute timings vary strongly with host load. Complexity remains bounded by
one `Q × N × 121` cross-moment pass plus cheap per-branch scalar work; adding
future response categories does not repeat the theta-grid dot products.

## Reproduction

```sh
python3 scripts/run_vocabulary_assessment_sensitivity.py \
  --suite development-sweep --paired-diagnostic-substreams --readers 32 \
  --adaptive-loss-population allNonExcluded \
  --question-objective evidenceSurrogate

python3 scripts/run_vocabulary_assessment_sensitivity.py \
  --suite development-sweep --paired-diagnostic-substreams --readers 32 \
  --adaptive-loss-population remainingUnasked \
  --question-objective evidenceSurrogate

python3 scripts/run_vocabulary_assessment_sensitivity.py \
  --suite development-sweep --paired-diagnostic-substreams --readers 32 \
  --adaptive-loss-population remainingUnasked \
  --question-objective latentKnowledgeRisk
```

Raw quality reports:

- `vocabulary-question-objective-legacy-2026-09-07.json`
- `vocabulary-question-objective-remaining-2026-09-07.json`
- `vocabulary-question-objective-latent-2026-09-07.json`

Raw Release benchmark reports use the matching `*-benchmark-2026-09-07.json`
names.
