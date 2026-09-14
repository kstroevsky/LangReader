# Vocabulary synthetic sensitivity report

Suite: `release-holdout`; version: `vocabulary-synthetic-holdout-v1`; runs: 3.

This is synthetic robustness evidence only. It does not validate probabilities or coverage on real learners.

| Scenario | Mode | Brier range | ECE range | Coverage-hit range | Questions range |
|---|---|---:|---:|---:|---:|
| idiosyncratic-knowledge | all-unknown | 0.1560–0.1583 | 0.0112–0.0222 | 100.0%–100.0% | 80.0–80.0 |
| idiosyncratic-knowledge | coverage-98 | 0.1590–0.1631 | 0.0141–0.0294 | 84.4%–92.2% | 80.0–80.0 |
| item-residual | all-unknown | 0.1159–0.1207 | 0.0149–0.0201 | 100.0%–100.0% | 79.7–80.0 |
| item-residual | coverage-98 | 0.1207–0.1262 | 0.0126–0.0190 | 95.3%–100.0% | 79.2–80.0 |
| response-noise | all-unknown | 0.1251–0.1307 | 0.0288–0.0348 | 100.0%–100.0% | 79.9–80.0 |
| response-noise | coverage-98 | 0.1302–0.1347 | 0.0280–0.0391 | 87.5%–96.9% | 79.8–80.0 |
| well-specified-rasch | all-unknown | 0.1110–0.1126 | 0.0265–0.0300 | 100.0%–100.0% | 80.0–80.0 |
| well-specified-rasch | coverage-98 | 0.1183–0.1195 | 0.0212–0.0250 | 100.0%–100.0% | 79.9–80.0 |

Eligible constituent engineering gates: failed
