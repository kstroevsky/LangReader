# Vocabulary assessment synthetic evaluation

Seed: `42`; readers/scenario: 1; documents/scenario: 1; lemmas/document: 20.

These are synthetic cold-start diagnostics, not evidence of calibration on real learners.

Assumed model: reliability scale 1.000; epsilon minimum 0.050; difficulty SD scale 1.000; coverage quantile 0.050; warm-prior weight 0.900; coverage stopping full-every-answer; loss population allNonExcluded; question objective evidenceSurrogate.
Random stream: frozen sequential evaluator stream.

| Scenario | Mode | Brier | Log loss | ECE | θ RMSE | 90% interval | Deck P/R | Token coverage | Target miss | Questions |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| well-specified-rasch | all-unknown | 0.0066 | 0.0470 | 0.0430 | 0.756 | 100.0% | 1.000 / 1.000 | 100.00% | 0.00% | 20.0 |
| well-specified-rasch | coverage-98 | 0.0045 | 0.0424 | 0.0399 | 0.448 | 100.0% | 0.824 / 0.933 | 98.13% | 0.00% | 20.0 |
| item-residual | all-unknown | 0.0037 | 0.0380 | 0.0360 | 0.124 | 100.0% | 1.000 / 1.000 | 100.00% | 0.00% | 20.0 |
| item-residual | coverage-98 | 0.0026 | 0.0302 | 0.0288 | 0.277 | 100.0% | 0.833 / 1.000 | 100.00% | 0.00% | 20.0 |
| response-noise | all-unknown | 0.1057 | 0.5047 | 0.1175 | 1.233 | 100.0% | 0.917 / 0.917 | 92.99% | 0.00% | 20.0 |
| response-noise | coverage-98 | 0.1547 | 0.6045 | 0.1968 | 0.527 | 100.0% | 0.571 / 1.000 | 100.00% | 0.00% | 20.0 |
| idiosyncratic-knowledge | all-unknown | 0.0429 | 0.1356 | 0.0933 | 1.513 | 100.0% | 1.000 / 0.800 | 94.97% | 0.00% | 20.0 |
| idiosyncratic-knowledge | coverage-98 | 0.0577 | 0.2091 | 0.1011 | 1.113 | 100.0% | 0.636 / 1.000 | 100.00% | 0.00% | 20.0 |

Quality gates: FAIL.
