# Vocabulary assessment synthetic evaluation

Seed: `7`; readers/scenario: 1; documents/scenario: 1; lemmas/document: 20.

These are synthetic cold-start diagnostics, not evidence of calibration on real learners.

Assumed model: reliability scale 1.000; epsilon minimum 0.050; difficulty SD scale 1.000; coverage quantile 0.050; warm-prior weight 0.900; coverage stopping full-every-answer; loss population allNonExcluded; question objective evidenceSurrogate.
Random stream: frozen sequential evaluator stream.

| Scenario | Mode | Brier | Log loss | ECE | θ RMSE | 90% interval | Deck P/R | Token coverage | Target miss | Questions |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| well-specified-rasch | all-unknown | 0.0465 | 0.1693 | 0.0603 | 0.163 | 100.0% | 1.000 / 0.929 | 94.97% | 0.00% | 20.0 |
| well-specified-rasch | coverage-98 | 0.0056 | 0.0394 | 0.0360 | 1.573 | 0.0% | 0.643 / 0.900 | 98.13% | 0.00% | 20.0 |
| item-residual | all-unknown | 0.0104 | 0.0588 | 0.0523 | 0.961 | 100.0% | 1.000 / 1.000 | 100.00% | 0.00% | 20.0 |
| item-residual | coverage-98 | 0.0246 | 0.0877 | 0.0660 | 0.097 | 100.0% | 0.500 / 1.000 | 100.00% | 0.00% | 20.0 |
| response-noise | all-unknown | 0.1269 | 0.4874 | 0.1410 | 0.552 | 100.0% | 0.800 / 0.667 | 92.21% | 0.00% | 20.0 |
| response-noise | coverage-98 | 0.1008 | 0.4609 | 0.1222 | 1.130 | 100.0% | 0.727 / 0.727 | 73.95% | 100.00% | 20.0 |
| idiosyncratic-knowledge | all-unknown | 0.0538 | 0.2678 | 0.0757 | 0.718 | 100.0% | 1.000 / 0.857 | 96.94% | 0.00% | 20.0 |
| idiosyncratic-knowledge | coverage-98 | 0.0072 | 0.0553 | 0.0511 | 0.143 | 100.0% | 0.750 / 1.000 | 100.00% | 0.00% | 20.0 |

Quality gates: FAIL.
