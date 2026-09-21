# POS validation v2 reporting repair

The first v2 scoring process evaluated the frozen cases but aborted before
writing any JSON because the downstream consequence simulator received one
candidate per corpus occurrence. Repeated lemma+POS identities caused its
unique-key assessment initialization to trap on `en|'s|particle|`.

No case output, aggregate metric, or held-out direction was emitted or inspected.
The bounded repair aggregates identical lemma+POS rows and sums their occurrence
weights before building the gold/predicted consequence assessments. It changes
neither NaturalLanguage predictions, production POS thresholds, fixture cases,
nor frozen selection. The same v2 fixture may be rerun solely to complete the
predeclared report, and this failed attempt remains recorded.
