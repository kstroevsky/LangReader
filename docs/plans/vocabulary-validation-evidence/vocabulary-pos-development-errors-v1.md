# Vocabulary POS development error decomposition

This analysis uses only the 160 frozen development cases. It does not reread held-out metrics, change thresholds, or authorize a production fix. Mechanism flags overlap.

| Population | Cases | Raw POS errors | Lemma errors | Abstentions | Recovered abstentions | Name exclusion errors | Final identity errors |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| All development | 160 | 41 | 9 | 16 | 1 | 6 | 50 |
| en development | 80 | 19 | 2 | 4 | 0 | 3 | 22 |
| de development | 80 | 22 | 7 | 12 | 1 | 3 | 28 |
| Assessable content words | 82 | 21 | 6 | 11 | 0 | 2 | 26 |
| en content words | 39 | 8 | 2 | 3 | 0 | 1 | 10 |
| de content words | 43 | 13 | 4 | 8 | 0 | 1 | 16 |

Occurrence mass equals case count in this UD sample because each sampled token has unit weight; private document occurrence weighting remains unmeasured.

Most useful next step: inspect development-only lemma errors, unresolved abstentions, and name-exclusion errors by language/POS before proposing any bounded change. A changed candidate requires regression tests and a fresh held-out reservation.
