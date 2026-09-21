# Vocabulary synthetic sensitivity report

Suite: `release-holdout`; version: `vocabulary-synthetic-holdout-v1`; runs: 3.

This is synthetic robustness evidence only. It does not validate probabilities or coverage on real learners.

| Scenario | Mode | Brier range | ECE range | Coverage-hit range | Questions range |
|---|---|---:|---:|---:|---:|
| idiosyncratic-knowledge | all-unknown | 0.1523–0.1579 | 0.0277–0.0313 | 100.0%–100.0% | 80.0–80.0 |
| idiosyncratic-knowledge | coverage-98 | 0.1594–0.1605 | 0.0299–0.0331 | 78.1%–84.4% | 77.9–78.5 |
| item-residual | all-unknown | 0.1178–0.1236 | 0.0074–0.0103 | 100.0%–100.0% | 80.0–80.0 |
| item-residual | coverage-98 | 0.1219–0.1281 | 0.0097–0.0135 | 90.6%–98.4% | 76.7–78.2 |
| response-noise | all-unknown | 0.1298–0.1325 | 0.0411–0.0453 | 100.0%–100.0% | 80.0–80.0 |
| response-noise | coverage-98 | 0.1366–0.1405 | 0.0306–0.0374 | 71.9%–79.7% | 77.3–78.3 |
| well-specified-rasch | all-unknown | 0.1108–0.1116 | 0.0182–0.0210 | 100.0%–100.0% | 80.0–80.0 |
| well-specified-rasch | coverage-98 | 0.1195–0.1214 | 0.0174–0.0215 | 95.3%–98.4% | 75.1–77.2 |

Eligible constituent engineering gates: failed
