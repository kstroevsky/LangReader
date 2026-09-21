# Vocabulary coverage-stopping development comparison

Paired runs: 3. This is development evidence, not the frozen release holdout or real-learner validation.

| Scenario | Mode | Δ Brier | Δ ECE | Δ coverage hit | Δ precision | Δ questions |
|---|---|---:|---:|---:|---:|---:|
| idiosyncratic-knowledge | all-unknown | +0.0000 | +0.0000 | +0.00% | +0.0000 | +0.00 |
| idiosyncratic-knowledge | coverage-98 | +0.0027 | +0.0023 | +0.00% | -0.0022 | -3.77 |
| item-residual | all-unknown | +0.0000 | +0.0000 | +0.00% | +0.0000 | +0.00 |
| item-residual | coverage-98 | +0.0009 | +0.0001 | +0.00% | -0.0014 | -1.98 |
| response-noise | all-unknown | +0.0000 | +0.0000 | +0.00% | +0.0000 | +0.00 |
| response-noise | coverage-98 | +0.0004 | -0.0013 | +1.04% | -0.0015 | -2.09 |
| well-specified-rasch | all-unknown | +0.0000 | +0.0000 | +0.00% | +0.0000 | +0.00 |
| well-specified-rasch | coverage-98 | +0.0014 | -0.0003 | +0.00% | -0.0020 | -3.16 |

Per-seed warm results:

- `20260830`: coverage 96.88% → 96.88%; questions 15.03 → 18.88.
- `20260831`: coverage 100.00% → 96.88%; questions 15.72 → 18.09.
- `20260832`: coverage 93.75% → 96.88%; questions 13.97 → 20.56.

Comparison gates: PASS.
