# Performance optimization audit

Audited on 2026-08-09 against the re-audited optimization plan. The retention
rule for code changes was unchanged output plus a repeatable improvement above
normal run-to-run noise. Optimizations that add architectural cost without a
measured interaction-path benefit remain deferred.

## Corrective re-audit

The first version of this audit overstated the reader-opening result. Its
`launch` event ended when the empty reader window appeared, and
`firstPageDisplay` ended when PDF geometry was assigned even though PDF tiles,
loading-overlay dismissal, transcript layout, and decoration restoration were
still outstanding. Those events did not measure the user's "document is
visibly usable" boundary. A slower user-visible open could therefore pass the
old gate, which is what happened.

The corrected gate records `documentVisibleReady` plus one format-specific
visible-ready event. Session restoration also records
`restoredDocumentVisibleReady` from process start. The original chrome is an
explicit UI contract: the signed Release build was checked against the supplied
screenshot and exposed all 18 required top/bottom controls.

## Implemented plan coverage

| Plan item | Current implementation | Status |
| --- | --- | --- |
| Stage-level evidence | `PerformanceEvent`, `ReaderPerformance`, signposts, deterministic JSON/text capture, and private fixture validation cover open, actual visible readiness, restored-document readiness, text snapshots, index build, save acknowledgement, occurrence query/persistence, database writes, visible highlights, web restoration, and search. | Implemented |
| Cache canonical text | PDF page text is cached in memory and across sessions; EPUB/DOCX source text is extracted once and reused by the web presentation. | Implemented |
| Avoid repeated NLP | `VocabularyDocumentLemmaIndex` is built once per document/language, bounded to four workers, seeded by the visible/current page slice, and reused by later saves and backfill. | Implemented |
| Cache regex/query work | Vocabulary queries compile once per scan; the EPUB sanitizer reuses compiled expressions; simple indexed tokens use postings instead of regex rescans. | Implemented |
| Cancellation/generation safety | PDF text/index builds, visible-first work, PDFKit search, web loading, and grouped posting scans are cancellable or generation-guarded. Replacing a vocabulary scan or changing document cancels the old work; cancelled grouped scans return no partial result. | Implemented |
| Batch database writes | Occurrence persistence and bulk metadata/SRS mutations use one transactional upsert per batch, with the existing full-snapshot retry only on failure. | Implemented |
| Batch invalidations | PDF annotations are added for visible pages and one display invalidation is issued per batch. Web marks update one CSS Highlight collection per category. | Implemented |
| Occurrence disambiguation | Stored web occurrence indexes are applied during restoration; semantic PDF anchors use unit ordinal, UTF-16 range, quote, prefix, and suffix. | Implemented |
| Visible-only geometry | Offscreen PDF occurrences persist semantic positions with zero geometry. PDF selections/bounds and annotations are resolved only for visible pages or explicit navigation. | Implemented |
| Async PDF Find | PDFKit `beginFindString` streams results, supports replacement/cancellation, and rejects stale notifications. | Implemented |
| Release measurement | Representative PDF/EPUB/DOCX captures and subsystem benchmarks are run against optimized builds rather than inferred from Debug code shape. | Implemented |
| In-memory index | Per-page canonical text, token ranges, exact surfaces, lemma postings, and line-wrap postings answer single and batch occurrence queries. | Implemented |
| Semantic lookup vs rendering | The selected occurrence is durably saved and acknowledged before whole-document discovery; visible work is prioritized and offscreen materialization is deferred. | Implemented |
| CSS Custom Highlights | Vocabulary, notes, AI sources, and search use CSS Custom Highlights without DOM mutation when supported, with a tested legacy fallback. | Implemented |
| Sparse web mappings | DOM normalization uses compressed mapping runs and a shared block index rather than one object per normalized character. | Implemented |

Sentence-boundary postings were not added to the vocabulary index: no current
query consumes them, while context extraction already uses bounded canonical
ranges. Adding unused postings would increase build time and retained memory
without improving a measured scenario.

## Retained experiments

All measurements below preserve output counts/content. Timings are milliseconds
on the same Apple Silicon development machine; individual samples are retained
because thermal and filesystem state make a single aggregate misleading.

| Experiment | Before | After | Result |
| --- | ---: | ---: | --- |
| Real German DOCX core load after sanitizer regex caching | pooled median 4,066.6 | pooled median 2,650.3 | Retained; every paired block was faster and output stayed at 782,265 HTML bytes, 511,340 text characters, 87 TOC items, 0 diagnostics. |
| Same-content 61 MB EPUB sanitizer guard | 211.3 / 133.0 | 203.6 / 133.3 | Retained; no regression and identical 60,559 HTML bytes, 7 TOC items, 0 diagnostics. |
| Update 2,000 vocabulary occurrences | 971.9–1,054.5 | 135.8–141.9 | Retained; one transaction is about 86% faster than one transaction per record. |
| Restore 2,000 lemma groups across 300 pages (90,000 results) | 2,607.0–9,448.3 | 213.2–347.1 | Retained; adaptive postings intersection and precomputed exact-surface keys remove per-page work proportional to the full saved vocabulary. |
| Common single-token lookup across 300 pages (721 results) | 54.4–61.3 | 2.4–3.0 | Retained; meets the plan's <10 ms median target. Punctuation-bearing tokens such as `E-Mail` retain the exact regex fallback. |
| Real 207-page German PDF open, delivered pre-fix Release vs corrected Release | PDF open 166.0–169.1; first-page setup 143.7–144.7 | PDF open 89.5–92.1; first-page setup 74.2–76.5 | Retained; balanced forward/reverse runs reduce both synchronous seams by about 46–49%. Corrected visible-ready median is 153.8–156.4. |

The reproducible subsystem commands are:

```sh
./scripts/benchmark_vocabulary_storage.sh 2000 3
./scripts/benchmark_vocabulary_index.sh 300 2000 5
```

The corrected representative capture measured PDF visible-ready at 165.5 ms
median, EPUB preparation/visible-ready at 158.7/393.1 ms, and DOCX
preparation/visible-ready at 1,885.6/2,089.8 ms. These values are the accepted
Release shipping capture; the earlier first-page value must not be presented as
an end-to-end readiness result.

## Deliberately deferred proposals

| Proposal | Evidence-based decision |
| --- | --- |
| Persistent token/postings database | Defer. Saves acknowledge immediately, the in-memory common lookup is 2.4–3.0 ms, and persistence would add parser/tokenizer versioning, invalidation, migration, and storage cost. Revisit only if warm-session index build or scrolling traces regress. |
| FTS5/trigram document index | Defer. It is useful for candidate retrieval, but PDFKit Find is already asynchronous and exact vocabulary lookup is below target. It would not be the semantic source of truth without a verifier. |
| PDF page overlay renderer | Defer. Visible annotation materialization is at or below 0.1 ms; replacing the renderer cannot produce a material user-visible gain at current scale. |
| EPUB/DOCX virtualization | Defer. EPUB is visibly ready in about 0.39 s. DOCX preparation is about 1.89 s of its 2.09 s visible-ready time, so archive/XML preparation remains the bottleneck; virtualization would add navigation, selection, and anchor complexity without attacking the measured stage. |
| Q-gram/edit-distance anchor recovery | Defer as a recovery tier. Current versioned sources first resolve stored UTF-16 position, then exact quote plus prefix/suffix context. No stale-source failure corpus justifies fuzzy recovery yet. |
| Suffix array/FM-index | Reject for current requirements. Postings and exact fallback cover the measured workloads with substantially lower complexity. |
| Persist every visual occurrence/geometry | Reject as identity. Semantic positions remain durable; geometry is a viewport cache materialized lazily. |

## Verification notes

- `swift test`: 28 tests passed.
- `scripts/run_tests.sh`: web, highlight, performance-capture, SQLite, personal-vocabulary, embedding, regression, theme, update-classification, reader chrome, and all German morphology/dictionary groups passed. The runner stops at the pre-existing environment-sensitive French `parler` lemma assertion because NaturalLanguage returned no inflected-form group. No corrective performance change touches that assertion.
- The shipping `--release` build completed with `-O`, ad-hoc signing, strict deep signature verification, and Sparkle framework validation. Optional locally installed TTS runtimes were absent and reported as non-fatal warnings.
- The signed app opened the supplied German PDF, EPUB, and DOCX twice, and the document-capture validator accepted the resulting JSON. The exact Release executable was then launched directly and its live accessibility tree contained 18/18 screenshot-contract controls. Balanced PDF comparisons used immutable binaries in forward and reverse order; build-time samples were discarded.
