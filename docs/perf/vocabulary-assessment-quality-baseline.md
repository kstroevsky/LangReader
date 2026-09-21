# Vocabulary assessment synthetic evaluation

Seed: `20260815`; readers/scenario: 64; lemmas: 400.

These are synthetic cold-start diagnostics, not evidence of calibration on real learners.

| Scenario | Mode | Brier | Log loss | ECE | θ RMSE | 90% interval | Deck P/R | Token coverage | Target miss | Questions |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| well-specified-rasch | all-unknown | 0.1023 | 0.3317 | 0.0117 | 0.283 | 92.2% | 0.874 / 0.868 | 93.23% | 0.00% | 79.1 |
| well-specified-rasch | coverage-98 | 0.1137 | 0.3606 | 0.0089 | 0.407 | 95.3% | 0.603 / 0.912 | 98.81% | 0.00% | 68.2 |
| item-residual | all-unknown | 0.1108 | 0.3527 | 0.0057 | 0.324 | 85.9% | 0.843 / 0.830 | 93.67% | 0.00% | 80.0 |
| item-residual | coverage-98 | 0.1200 | 0.3765 | 0.0061 | 0.438 | 89.1% | 0.591 / 0.902 | 98.69% | 3.12% | 67.7 |
| response-noise | all-unknown | 0.1276 | 0.8357 | 0.0578 | 0.371 | 84.4% | 0.833 / 0.794 | 91.62% | 0.00% | 80.0 |
| response-noise | coverage-98 | 0.1353 | 0.8026 | 0.0455 | 0.381 | 95.3% | 0.607 / 0.904 | 96.68% | 75.00% | 71.3 |
| idiosyncratic-knowledge | all-unknown | 0.1467 | 0.4449 | 0.0371 | 0.433 | 81.2% | 0.812 / 0.762 | 90.65% | 0.00% | 80.0 |
| idiosyncratic-knowledge | coverage-98 | 0.1542 | 0.4641 | 0.0390 | 0.493 | 85.9% | 0.577 / 0.876 | 98.36% | 15.62% | 74.3 |

Quality gates: PASS.
