# Warm question-path forensic attempt v1 — retained reporting failure

The selected 11-case run completed from clean source revision `11844eb` and its
schema-4 validator passed. All cold/warm natural and fixed-budget paths match the
consumed 1,024-row source report exactly across question count, answer path,
posterior, selected-deck fingerprint, missed occurrence mass, realized coverage,
and conservative coverage.

The report nevertheless cannot satisfy the frozen forensic contract. It records
all asked-item traces but does not retain final rows for unasked inventory items.
Since final decks may select unasked items, selected-deck symmetric-difference
occurrence mass cannot be reconstructed from counts and fingerprints.

The following artifacts are retained rather than overwritten:

- [Semantic report](warm-question-path-forensic-report-v1.json), SHA-256
  `14bd07c1c2cd0a2df97b4e2b683169411cb5d59eb13cd43fad6db406adb364bf`.
- [Concise evaluator report](warm-question-path-forensic-report-v1.md).
- [Raw timings](warm-question-path-forensic-timing-v1.json).

No mechanism conclusion or production decision is drawn from this incomplete
attempt. A repair must be separately frozen and limited to adding final inventory
rows; selected run IDs, paths, hidden truth, responses, and analysis definitions
must remain unchanged.
