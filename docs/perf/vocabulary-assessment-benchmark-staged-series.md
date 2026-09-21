# Vocabulary assessment benchmark series

Runs: 3; all 10,000-lemma p95 gates passed: yes

| Lemmas | Mode | Profile | p50 range ms | p95 range ms | Maximum range ms |
|---:|---|---|---:|---:|---:|
| 100 | all-unknown | cold | 0.68–0.70 | 0.77–0.88 | 0.80–0.89 |
| 100 | coverage-98 | cold | 1.01–1.04 | 1.13–1.33 | 1.28–1.44 |
| 1000 | all-unknown | cold | 4.51–5.19 | 5.10–5.72 | 5.23–5.87 |
| 1000 | coverage-98 | cold | 5.59–6.64 | 6.69–8.70 | 6.94–10.04 |
| 5000 | all-unknown | cold | 21.36–37.61 | 24.25–55.71 | 25.15–70.76 |
| 5000 | coverage-98 | cold | 34.00–44.40 | 47.30–57.38 | 54.89–59.24 |
| 10000 | all-unknown | cold | 58.90–62.50 | 72.79–74.75 | 76.94–86.76 |
| 10000 | coverage-98 | cold | 74.61–84.21 | 103.37–119.55 | 114.41–136.39 |
| 10000 | coverage-98 | warm | 99.39–105.40 | 117.76–121.37 | 122.52–127.68 |

Auxiliary phase trends (not part of the 150 ms next-card gate):

| Measurement | p50 range ms | p95 range ms |
|---|---:|---:|
| coverage-final-result-10000 | 115.61–124.54 | 120.47–126.21 |
| coverage-stop-check-10000 | 148.46–166.82 | 150.81–167.63 |
| pos-indexing-10000-tokens | 769.01–862.93 | 800.77–896.74 |
| research-export-5000 | 90.28–110.76 | 110.52–112.86 |
| session-migration | 0.03–0.03 | 0.03–0.03 |

The reports retain every raw sample and environment/source metadata. A failed run is not removed from the series.
