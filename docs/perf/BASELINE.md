# Performance baseline (Phase 0.4)

The plan gates every high-frequency UI migration on a before/after measurement
(principle 7). This is the "before". A migration of a surface listed here is not
done until its number is at least as good as this file records.

## How the numbers are produced

Instrumentation is a thin layer over a platform-neutral recorder:

* `LeafReaderCore/Performance/` — `PerformanceRecorder` collects timing samples
  and `PerformanceReport` retains them in observation order, summarises them
  (min / median / mean / max), and serialises schema-v2 JSON deterministically.
  Unit-tested; no AppKit.
* `LeafReaderApp/App/ReaderPerformance.swift` — the app facade. It adds an
  `os_signpost` interval per measurement (so the same runs profile in
  Instruments) and is a **no-op unless `LEAFVOCAB_PERF=1`**, so instrumentation
  sits directly on `loadPDF` / `applyReaderTheme` without costing a normal
  launch anything.

Each measured surface calls `ReaderPerformance.begin`/`end` (or the AI path
records latency where the stream delta arrives). On quit the app writes the
report to `LEAFVOCAB_PERF_OUT`.

### Reproduce

```sh
swift scripts/make_perf_fixtures.swift /tmp/leaf-perf-fixtures   # small.pdf, large.pdf
SPARKLE_HOME="…/Frameworks" ./scripts/build_app.sh --release
./scripts/capture_perf_baseline.sh /tmp/leaf-perf-fixtures docs/perf/baseline
```

The capture script drives the real bundle through Apple Events, so `loadPDF`
runs exactly as it does for a user. Cold and warm paths are separate process
phases and separate artifacts (`*.cold.json` and `*.warm.json`). Each JSON row
contains `samples_ms`; metadata identifies the Release binary hash, source
revision, phase, OS, architecture, fixture-set digest, and run ID. The validator
recomputes every aggregate from the raw samples and rejects stale, mixed-phase,
undersampled, or non-visible captures.

The non-DOCX format and interaction gates are:

```sh
./scripts/capture_perf_baseline.sh --matrix-fixtures \
  clean-300.pdf complex.pdf ocr.pdf normal.epub large.epub \
  docs/perf/non-docx-matrix

./scripts/capture_perf_baseline.sh --interaction-fixtures \
  clean-300.pdf normal.epub \
  docs/perf/non-docx-interaction
```

The matrix requires three visibly ready PDFs and two visibly ready EPUBs in
each phase. The interaction gate covers query acknowledgement, first visible
result, cancellation, repeated navigation, save acknowledgement, indexed
occurrence lookup, visible highlights, zoom/font updates, main-thread p95, and
idle-versus-background-index paging delay. `scripts/profile_running_app.sh`
adds an Instruments Time Profiler or Animation Hitches trace plus a 10 Hz
CPU/RSS series without changing the JSON acceptance run.

The DOCX gate gives each cold/warm pair its own prepared-cache root and checks
that cold captures contain extraction/render/commit stages while warm captures
contain a cache-hit load and no extraction or XML render:

```sh
swift scripts/make_docx_perf_fixture.swift /tmp/leafreader-all-constructs.docx

./scripts/capture_docx_performance.sh \
  representative.pdf representative.epub primary.docx \
  /tmp/leafreader-docx-primary 5

swift scripts/summarize_docx_performance.swift --accept-primary \
  /tmp/leafreader-docx-primary/pair-1.cold.json /tmp/leafreader-docx-primary/pair-1.warm.json \
  /tmp/leafreader-docx-primary/pair-2.cold.json /tmp/leafreader-docx-primary/pair-2.warm.json \
  /tmp/leafreader-docx-primary/pair-3.cold.json /tmp/leafreader-docx-primary/pair-3.warm.json \
  /tmp/leafreader-docx-primary/pair-4.cold.json /tmp/leafreader-docx-primary/pair-4.warm.json \
  /tmp/leafreader-docx-primary/pair-5.cold.json /tmp/leafreader-docx-primary/pair-5.warm.json
```

Pass cold/warm files as adjacent pairs to the summarizer when invoking it
directly. The capture wrapper supplies the correct order automatically and
verifies that the Release executable hash does not change during the run.

For the representative gate, copy `private-fixtures.example.json` to the
gitignored `private-fixtures.json`, replace the three paths, and record the
actual sizes of the long-conversation, notes, and vocabulary datasets:

```sh
cp docs/perf/private-fixtures.example.json docs/perf/private-fixtures.json
./scripts/capture_perf_baseline.sh \
  --private-manifest docs/perf/private-fixtures.json \
  docs/perf/representative-baseline
```

The manifest validator requires PDF, EPUB, and DOCX fixtures plus at least 100
AI messages, 100 notes, and 1,000 vocabulary records. The script opens every
document twice (cold and warm paths), then pauses while the operator exercises
Shelf, Notes, Vocabulary Library, a long AI conversation, selection tools, and
theme switching. It writes the aggregate report and a separate
`representative-baseline.fixtures.json`. That sidecar contains only generic
aliases, formats, byte counts, and dataset counts — never source paths or file
names. The private manifest and documents must not be committed.

## Historical synthetic reference

Captured 2026-07-27 on Apple Silicon, Command Line Tools toolchain, debug build.
Small sample counts — this is a v1 reference, not a statistical distribution;
re-run to tighten it.

| Surface | n | min | median | mean | max |
|---|--:|--:|--:|--:|--:|
| App launch | 1 | 129.0 | 129.0 | 129.0 | 129.0 |
| Main window | 1 | 127.0 | 127.0 | 127.0 | 127.0 |
| PDF open | 4 | 32.3 | 69.0 | 493.5 | 1803.6 |
| First page display | 4 | 8.5 | 42.9 | 413.5 | 1559.5 |
| Theme switch | 5 | 2.4 | 4.2 | 50.1 | 232.1 |

All values are milliseconds.

`First page display` is a historical synchronous-layout seam, not an
end-to-end usability metric: PDFKit can still be rasterising tiles and the
reader can still be dismissing its loading state afterwards. New captures must
use `PDF visibly ready` / `Document visibly ready` for user-perceived opening
and retain `First page display` only as a diagnostic substage.

### Fixtures

* **small.pdf** — 2 pages, ~0.5 MB. The fast path (`PDF open` ≈ 32 ms).
* **large.pdf** — 240 image-rendered pages, ~113 MB. A deliberate stress case;
  it is what produces the `PDF open` max of ~1.8 s and the `First page display`
  max of ~1.6 s. A typical text-based book sits between the two.
* **large vocabulary database** — the machine's real `word-records.sqlite3`
  (~0.4 MB) backs the Vocabulary Library timing when that surface is exercised.

## Additional opt-in surfaces

These surfaces have `begin`/`end` calls in place, so they appear in the report
the moment they are exercised with `LEAFVOCAB_PERF=1` — they are simply not in
the automated run:

* **EPUB / DOCX open** (`webOpen`) — needs an EPUB/DOCX fixture; open one by
  hand under the two environment variables.
* **Shelf open**, **Notes open**, **Vocabulary Library open**,
  **AI panel expansion**, **Selection toolbar** — need UI driving; open each
  once during a captured session and it lands in the report.
* **AI first token** / **AI streaming** — need a configured model, which this
  machine deliberately does not have. Latency is recorded where the stream
  delta arrives, before the main-queue hop, so the number reflects the
  model/network rather than UI scheduling.

The repository does not contain private documents, so the representative
aggregate remains a machine-local release checkpoint until an operator supplies
the manifest above. The synthetic baseline remains the checked-in measurement
plumbing reference; it must not be presented as the representative gate.

## Prepare Vocabulary quality and performance

The pre-reading assessment has a separate reproducible contract covering its
frequency-based model limits, fixed-seed synthetic quality gates, optimized
100–10,000-lemma response-time benchmark, same-machine inventory trend, and
private six-format/language app capture. See
[Prepare Vocabulary: model and measurement contract](VOCABULARY_PREPARATION.md).

The checked-in reports are
`vocabulary-assessment-quality-baseline.json`,
`vocabulary-assessment-quality-baseline.md`, and
`vocabulary-assessment-benchmark.json`. Synthetic results are engineering
regression evidence only; they are not empirical learner calibration.

## Notes / debt

The Vocabulary Library was migrated to SwiftUI before this instrumentation
existed, so it has no pre-migration number to compare against — its first
captured value becomes its own reference, and any future change to it is gated
from there.
