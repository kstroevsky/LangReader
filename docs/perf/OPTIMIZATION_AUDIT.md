# Performance optimization audit

Final non-DOCX acceptance audit: 2026-08-09. DOCX was expressly excluded from
this pass. No DOCX result is used to claim completion below.

The central diagnosis from the initial plan was correct: user-visible cost came
from repeated extraction/NLP and eager conversion of semantic matches into
native visual objects, not from scanning a book-sized cached string. The final
implementation therefore caches canonical text, builds reusable postings,
persists semantic anchors, and materializes visual ranges only where needed.

## Acceptance result

The non-DOCX scope is complete against the initial plan and the later corrective
audit. The signed Release binary at source revision `33ff1c4` passed:

- cold and warm format matrices using a clean 300-page PDF, complex-layout PDF,
  OCR PDF, normal EPUB, and a real 61 MB EPUB;
- an interaction matrix covering search acknowledgement/result/cancellation,
  repeated navigation, save acknowledgement, occurrence lookup, visible
  highlight application, zoom/font changes, main-thread stalls, and scrolling
  while indexing;
- an Instruments Time Profiler capture and an Animation Hitches capture;
- strict deep code-signature verification; and
- a live UI-contract check on the supplied 207-page German PDF.

The exact Release executable SHA-256 was
`151a19f687023ed9c77532c55092661b924a6c93993e39e4ec9ac367d4a60044`.

## Initial-plan coverage

| Initial proposal | Resolution | Evidence/status |
| --- | --- | --- |
| 1. Persistent positional index | Measurement-gated, as the revised plan required | Deferred: warm indexed lemma lookup is 1.3 ms. Persisting postings would add migrations, tokenizer/parser versioning, storage, and invalidation without a measured interaction benefit. |
| 2. Do not extract/lemmatize unchanged text twice | Implemented | PDF canonical page text has memory and disk caches; each open document/language owns one reusable `VocabularyDocumentLemmaIndex`. Indexing runs once, visible-first, with bounded background completion. |
| 3. Do not assume raw substring search is the bottleneck | Implemented and verified | Search, indexing, persistence, database work, and visual materialization are independently timed. Web literal search uses a lightweight text-node scan rather than building the full normalized mapping. |
| 4. Aho-Corasick for fixed batch matching | Correctly not generalized | The current postings-based batch restore is already fast. No measured multi-pattern workload justifies another engine. |
| 5. FTS5 as candidate retrieval | Measurement-gated | Deferred: async PDFKit literal search and cached/postings lookup meet every interaction gate. FTS5 would still need LangReader's semantic verifier. |
| 6. Suffix array/FM-index | Rejected | Disproportionate to one open book and the measured query latency. |
| 7. Q-gram recovery | Recovery-tier only | Exact position/quote/context resolution is implemented. No stale/OCR anchor corpus currently demonstrates a need for approximate recovery. |
| 8. Semantic positions, not geometry, as identity | Implemented | PDF records persist page/unit ordinal, UTF-16 range, quote, prefix, and suffix. Geometry remains viewport/layout-derived state. |
| 9. Materialize PDF selections only when needed | Implemented | Offscreen matches retain semantic positions. The selected match resolves directly; visible-page selections and annotations are applied incrementally in batches of eight. |
| 10. PDF page-overlay renderer | Prototyped by measurement, then deferred | Current visible highlight materialization is 0.5–1.7 ms and produced zero Animation Hitches. An overlay rewrite cannot presently deliver a material gain. |
| 11. Asynchronous PDF Find | Implemented | `beginFindString` streams results, supports replacement/cancellation, and rejects stale notifications. |
| 12. CSS Custom Highlights | Implemented | Vocabulary, note, AI-source, and search highlights use non-mutating highlight collections with tested fallback behavior. Search first paints the current result and materializes the remainder in batches. |
| 13. Replace per-character web mappings | Implemented | Normalized DOM positions use compressed text runs and sparse correction data; simple literal search bypasses the full mapping entirely. |
| 14. EPUB virtualization | Measurement-gated | Deferred: the real 61 MB EPUB is visibly ready in 716.0 ms cold and 387.8 ms warm at worst. The interaction trace does not justify the navigation/selection complexity of virtualization. |
| 15. Structured cancellation | Implemented | PDF text/index work, visible-first work, PDFKit search, web loading, and grouped scans are cancellable or generation-guarded. |
| 16. Isolated index ownership without per-token actor hops | Implemented in equivalent form | Workers build local page buffers and merge bounded batches into document-owned state; CPU work is not serialized one token at a time. |
| 17. Bounded parallelism | Implemented | NLP/index work is capped at four workers and yields to current reader input. Profiling confirms CPU work is off the main thread. |
| 18. Visible-first indexing | Implemented | Current/visible PDF units are prioritized. Whole-book completion remains explicitly separate from visible readiness and interaction acknowledgement. |
| 19. Do not persist visual occurrences unnecessarily | Implemented within existing product semantics | Durable records contain semantic anchors; native selections, DOM ranges, and geometry are derived lazily. Transactional batch upserts remove per-record write amplification. |

The plan's Phase 0–4 work is therefore implemented. Phase 5 was explicitly
conditional on measurements; the measurements reject it for now. Sentence
boundaries were also deliberately omitted because no current query consumes
them and bounded canonical ranges already supply context.

## Corrective work found during the audit

The first performance report was not sufficient. It ended PDF readiness after
geometry assignment rather than visible usability, had no raw samples or
cold/warm separation, and its automated “scroll” scenario used page jumps. The
following corrections are now part of the repository:

- schema-v2 reports retain every raw sample plus source revision, Release
  binary hash, phase, OS/architecture, fixture-set digest, and run ID;
- the validator recomputes aggregates and rejects mixed, stale, undersampled,
  non-Release, or non-visible captures;
- cold and warm phases use separate processes and artifacts;
- cache identity includes a streaming content SHA-256, with a regression test
  for same path, byte count, and modification time but changed content;
- the interaction script performs real clip-view scrolling;
- automation is gated by `LEAFVOCAB_PERF_AUTOMATION=1` and normal launches keep
  the original UI and behavior;
- background snapshot/index work is deferred for 250 ms after reader input;
- common posting lists are merged in order without a string-key set and final
  resort; and
- exact PDF semantic anchors resolve directly rather than rescanning a page for
  every stored occurrence.

Those last two fixes reduced a live common-word query from 15.3 ms to 1.3 ms
and visible highlight materialization from 362.8 ms to 1.7 ms.

## Accepted measurements

All times are milliseconds. Raw samples, not just aggregates, are committed in
the linked JSON artifacts.

### Cold/warm format matrix

| Phase and event | Minimum | Median | Maximum |
| --- | ---: | ---: | ---: |
| Cold PDF open (3 fixtures) | 88.0 | 93.4 | 134.6 |
| Cold PDF visible-ready | 119.3 | 119.6 | 267.3 |
| Cold EPUB preparation (2 fixtures) | 198.0 | 429.3 | 660.5 |
| Cold EPUB visible-ready | 384.5 | 550.2 | 716.0 |
| Warm PDF open (3 fixtures) | 77.2 | 91.2 | 133.1 |
| Warm PDF visible-ready | 107.6 | 120.0 | 273.2 |
| Warm EPUB preparation (2 fixtures) | 140.5 | 163.2 | 185.9 |
| Warm EPUB visible-ready | 196.4 | 292.1 | 387.8 |

Artifacts:
`non-docx-matrix.cold.json`, `non-docx-matrix.cold.txt`,
`non-docx-matrix.warm.json`, and `non-docx-matrix.warm.txt`.

### Interaction matrix

| Gate | Accepted result | Target |
| --- | ---: | ---: |
| Search acknowledgement, maximum | 1.1 | <16 |
| First visible search result, maximum | 12.0 | <50 |
| Search cancellation, maximum | 0.0 | <50 |
| Save acknowledgement | 42.0 | <50 |
| Indexed occurrence lookup | 1.3 | <10 median |
| Visible highlight materialization | 0.5–1.7 | <100 |
| Search navigation, maximum | 8.2 | interactive |
| PDF zoom update, maximum | 2.3 | interactive |
| Theme switch, maximum | 15.4 | interactive |
| Main-thread uninterrupted work, maximum | 4.2 | not routinely >16 |
| Idle scroll delay, median/maximum | 1.7 / 3.4 | reference |
| Background-index scroll delay, median/maximum | 1.5 / 7.0 | no detectable degradation |

The complete artifact is `non-docx-interaction.interaction.json`, with a
human-readable companion `.txt` file. It also records snapshot/index/database
background completion separately so those totals cannot be confused with
interaction latency.

### Instruments and resource evidence

The corrected Time Profiler run sampled 291 points at 10 Hz: peak resident
memory was 243,328 KB, mean process CPU was 97.01%, and peak CPU was 214.4%.
Hot stacks were bounded background `NaturalLanguage`/CoreNLP work inside
`VocabularyDocumentLemmaIndex`, not the main-thread interaction path.

The Animation Hitches trace covered 30.45 seconds of the exercised interaction
window and exported zero hitch rows. During the first 30 seconds, peak resident
memory was 304,528 KB and mean CPU was 111.63%; CPU fell after indexing
completed. The committed resource series and exported summary are:

- `non-docx-time-profile-resources.csv`
- `non-docx-animation-hitches-resources.csv`
- `non-docx-animation-hitches-summary.xml`

The full `.trace` bundles remain machine-local because they are large binary
Instruments artifacts; the raw resource time series and hitch export are
committed for review.

## UI preservation

The signed Release app was opened with `Alle Information от 14.07.26.pdf` and
its live accessibility tree contained every screenshot-contract control:
cover/title, related forms, Read, zoom out/value/in, page navigation, search,
Two-up, Crop, settings, Shelf, Words, Review, Notes, and TOC. The AI assistant
panel and its collapse control also remained present. No performance automation
runs in an ordinary launch.

## DOCX audited optimization (2026-08-11)

Fresh profiling of the 6.19 MB XML-heavy German fixture found that archive
extraction was not the limiting stage. The old renderer repeatedly created and
rescanned large XML `String` slices with nested regular expressions. The
replacement uses namespace-aware `XMLParser` delegates to render HTML, plain
text, and the TOC together, then persists validated prepared entries keyed by
the full document SHA-256, parser schema, and presentation title. Cache hits
load `rendered.html` through the existing `WKWebView.loadFileURL` path. Opening
a newer document cancels superseded parsing and removes its temporary build.

The final signed arm64 Release executable had SHA-256
`dfc264cec1cc87b13aa722cedb5587e9b432e88e2f8b3abd503c4f52bdd6cb4b`.
Five primary pairs used separate empty cache roots; each warm run reused only
its paired cold entry. Times are milliseconds.

| Primary metric | Old baseline | Final median | Improvement | Acceptance |
| --- | ---: | ---: | ---: | --- |
| Cold preparation | 1,745.4 | 493.9 | 71.7% | PASS (at least 50%) |
| Cold visible-ready | 2,028.3 | 684.9 | 66.2% | PASS (at least 50%, at most 1,000 ms) |
| Warm preparation | 1,750.7 | 6.1 | 99.7% | PASS (at least 70%) |
| Warm visible-ready | 1,950.2 | 208.4 | 89.3% | PASS (at least 70%, at most 500 ms) |

The individual primary measurements are recorded in
`docx-performance-summary.csv`. The media-heavy holdout prepared in 23.6 ms
cold and 2.3 ms warm, reaching visible-ready in 62.6/46.9 ms. The deterministic
all-construct fixture prepared in 129.4/3.1 ms and reached visible-ready in
239.9/136.4 ms. Cold stage telemetry attributed the primary median chiefly to
about 422 ms of streaming XML rendering and 53 ms of selective extraction;
warm runs contained fingerprint, lookup, and cache-hit-load events but no
extraction or XML-render event.

A 15-second cold-open Time Profiler capture sampled peak RSS at 139,424 KB,
28.5% below the 195,120 KB reference and below the allowed 214,632 KB limit.
A separate 15-second Animation Hitches capture exported zero hitch rows. The
reference German PDF then passed all 50 accessibility-based screenshot-contract
UI checks, including related forms, Read, zoom/page/search controls, Two-up,
Crop, Shelf, Words, Review, Notes, TOC, and AI-panel actions. PDF and EPUB code
paths were not changed; their contemporaneous capture events remained present
and valid in all five pairs.

Verification included exact real-fixture plain-text and TOC parity,
canonicalized body-DOM parity, 15 focused parser/cache tests, a strict Swift 6
build, and 47 package tests with zero failures (one optional private-fixture
test skipped in the generic run after passing separately). The legacy harness
passed every DOCX case and still ends on two unrelated vocabulary expectations:
French `parler` grouping and a now-resolved German `Häuser` known-gap assertion.
The repository-wide native-view seam check also reports two unchanged existing
allowlist violations in `ReaderWindowController+DocumentText.swift` and
`ReaderWindowController+PerformanceAutomation.swift`.

## Deferred work and re-entry thresholds

These are not missing implementation tasks; each is a measurement-triggered
option from the original plan.

| Option | Revisit only when |
| --- | --- |
| Persistent postings / FTS5 / trigram | indexed query median exceeds 10 ms, warm rebuild delays interaction, or general Find has a demonstrated corpus failure |
| PDF overlay renderer | visible highlight materialization exceeds 100 ms, annotations cause hitches, or export semantics require a separate layer |
| EPUB chapter virtualization | a representative EPUB exceeds the visible-ready budget, WebKit memory is unbounded, or scrolling/layout profiles show the monolithic DOM as the bottleneck |
| Q-gram/edit-distance recovery | a versioned stale/OCR anchor corpus shows unacceptable exact quote/context failures |
| Aho-Corasick | a measured fixed multi-pattern rebuild beats postings poorly enough to matter to users |
| Suffix/FM index | no current re-entry condition; not appropriate at this corpus size |

## Verification

- `swift test`: 32/32 passed on the final source revision after packaging.
- Focused vocabulary-index and PDF/web reader tests pass after the final query
  and highlight changes.
- The web reader search suite and positive/negative performance-validator suites
  pass.
- `scripts/run_tests.sh` passes the performance, reader, web, database, German
  morphology, theme, and UI-contract groups; it still stops at the pre-existing
  environment-sensitive French `parler` assertion where NaturalLanguage returns
  no inflected-form group.
- The Release app is ad-hoc signed and passes `codesign --verify --deep --strict`.

The reproducible commands and fixture requirements are documented in
`docs/perf/BASELINE.md`.
