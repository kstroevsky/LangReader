# Performance baseline (Phase 0.3)

The plan gates every high-frequency UI migration on a before/after measurement
(principle 7). This is the "before". A migration of a surface listed here is not
done until its number is at least as good as this file records.

## How the numbers are produced

Instrumentation is a thin layer over a platform-neutral recorder:

* `LeafReaderCore/Performance/` — `PerformanceRecorder` collects timing samples
  and `PerformanceReport` summarises them (min / median / mean / max) and
  serialises deterministically. Unit-tested; no AppKit.
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
SPARKLE_HOME="…/Frameworks" ./scripts/build_app.sh
./scripts/capture_perf_baseline.sh /tmp/leaf-perf-fixtures docs/perf/baseline
```

The capture script drives the real bundle through Apple Events, so `loadPDF`
runs exactly as it does for a user. `docs/perf/baseline.json` is the committed
machine-readable copy; diff it after a change.

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

## What this run captured

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

## Instrumented but not captured here

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

## Notes / debt

The Vocabulary Library was migrated to SwiftUI before this instrumentation
existed, so it has no pre-migration number to compare against — its first
captured value becomes its own reference, and any future change to it is gated
from there.
