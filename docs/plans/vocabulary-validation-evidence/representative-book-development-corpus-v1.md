# Representative-book development corpus v1

## Status

This corpus is development-only evidence for ADR-0001 lexical reconciliation.
It is not a held-out or release-gating corpus. The source documents and
candidate predictions have already been inspected, so neither document nor any
other pages from the same documents may later be promoted into a fresh holdout.

The repository stores provenance and sampling metadata only. Extracted book
prose remains in local annotation templates outside the repository.

## Sources

| Alias | Language | Genre | Pages | Source SHA-256 | Candidate anchors | Review occurrences | Sampled tokens |
| --- | --- | --- | ---: | --- | ---: | ---: | ---: |
| `martin-eden-en` | English | literary fiction | 213 | `c114c1e76c02d98b79a6d0f1e286ebd0bba48513b7a62bd6365cf58196ed8178` | 80 | 759 | 20,001 |
| `martin-eden-de` | German | literary fiction | 515 | `df95cd3d3092740d0fa4c21a177d8a7e02e1438d76e92694528c0f0c706db741` | 80 | 389 | 8,328 |

Safe repository metadata:

- `martin-eden-en-development-metadata-v1.json`
- `martin-eden-de-development-metadata-v1.json`

Local annotation templates containing extracted prose:

- `/Users/a.stroevskaya/Desktop/Martin-Eden-EN-adr0001-development-annotation-v1.json`
- `/Users/a.stroevskaya/Desktop/Martin-Eden-DE-adr0001-development-annotation-v1.json`

Each local occurrence now carries a sampled-unit index plus UTF-16
location/length, and each template carries the sampled-text SHA-256. These are
used to match a human-reviewed occurrence to the exact immutable production
Core observation before a lexical-partition fixture can be materialized.

## Review and materialization policy

NaturalLanguage output is candidate-prioritization evidence only. It must not
be copied into `goldLemma` or `goldPartOfSpeech` as truth. All retained rows are
currently `unreviewed`, with blank gold fields.

After human review, only rows marked `approved` may be materialized. The
materializer rechecks the source PDF hash and page count, re-extracts the exact
sampled pages, verifies the sampled-text hash, builds
`VocabularyDocumentLemmaIndex` through production Core, and matches approved
rows by sampled unit and UTF-16 range. A missing, duplicate, or changed surface
is rejected.

The emitted fixture uses human-reviewed lemma/POS labels with the actual Core
morphological analyses and context fingerprints. It also records observed
anchor mismatches so model lemma/alignment failures remain visible. No Martin
Eden lexical-partition score should be produced until reviewed gold labels
exist.

## Remaining coverage

These two novels provide literary-fiction development evidence only. ADR-0001
still needs multiple genres, English and German, PDF/EPUB/DOCX coverage,
supported macOS/NaturalLanguage runtimes, NLP available/unavailable strata, and
dictionary-attestation available/unavailable strata.

Fresh held-out evidence must be designated before inspection and come from
different documents/authors/genres. Consumed UD held-out material remains
unavailable for tuning or candidate comparison, and the current v17
lexical-reconciliation development-confirmation reservation remains sealed and
unexecuted.
