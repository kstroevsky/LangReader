# LeafReader Architecture

This document describes the current architecture that new work should extend. It is intentionally concise. Historical migration details belong in `docs/plans/`; generated inventories belong in `docs/wiki/`.

Canonical product terminology lives in `CONTEXT.md`.

## 1. Architectural Priorities

When tradeoffs conflict, prefer:

1. correctness and preservation of user-owned data;
2. smooth reader interaction and responsiveness;
3. preservation of established user-visible behavior;
4. clear state ownership and platform boundaries;
5. testability and maintainability;
6. architectural uniformity.

LeafReader is intentionally a SwiftUI + AppKit hybrid. Native framework use is a design choice, not unfinished migration by itself.

## 2. Module Boundary

The Swift package has two production targets:

```text
LeafReaderCore
      ↑
LeafReaderApp
```

Both build in Swift 6 mode.

### `LeafReaderCore`

Core is the domain/shared-logic module.

It contains logic whose meaning does not depend on macOS controls, windows, layout, or rendering frameworks, such as:

- document-processing semantics;
- semantic reader selection;
- vocabulary normalization, identity, SRS, and occurrence-save rules;
- reading-note and AI-conversation domain models/policies;
- parsing and document loading for EPUB/DOCX and other reusable processing;
- persistence formats, backup/compatibility logic, and deterministic policies;
- performance-recording primitives and other platform-neutral support.

Examples of the intended direction include `ReaderSelectionState`, `ReaderFocusedSelection`, and `VocabularyOccurrenceSavePlanner`.

Framework-free code is not automatically Core code. Presentation models and control/layout descriptions stay in the App even if they import only Foundation.

The Core boundary is mechanically checked by:

- `scripts/check_core_portable.sh`;
- `scripts/check_core_semantics.sh`.

### `LeafReaderApp`

App owns the macOS application layer:

- AppKit and SwiftUI presentation;
- PDFKit/WebKit integration;
- presentation models and state;
- settings UI;
- native speech/runtime integration;
- reader adapters;
- stores/services that are currently macOS/application-specific;
- feature coordination and composition.

Major feature areas are organized under:

```text
AIConversation/
DocumentReading/
ReadAloud/
ReaderShell/
ReadingNotes/
Settings/
SharedUI/
VocabularyReview/
Platform/
```

Do not create `LeafReaderSharedUI` preemptively. A separate shared presentation module should exist only when a second platform produces a real sharing boundary.

## 3. Reader Composition

`ReaderWindowController` is the macOS Reader Shell composition root.

It owns native reader lifetimes and connects document state, feature state, panels, stores, coordinators, and platform adapters. It also implements native delegates required by PDFKit/WebKit/AppKit.

Its size is known architectural debt, but size alone is not a reason for another rewrite.

New feature logic should make the controller more coordinative, not more algorithmic. Extract a model/coordinator/service/policy when there is a concrete ownership, reuse, or testability benefit.

Existing controller forwarding properties, especially document-state projections, are migration/compatibility seams. Do not grow a parallel state API around the controller when the underlying owner can be used directly.

## 4. Document Session and State Ownership

`DocumentSession` is the document-scoped container used while one document is open.

It currently holds/coordinates:

- file URL and bookmark identity;
- document ID/MD5;
- document kind;
- load generation;
- semantic selection;
- selection presentation;
- web presentation/progress state;
- reading position;
- reader presentation scalars;
- session-restore state.

Load generation is part of stale-result protection: work started for an old document load must not become authoritative after another load replaces it.

### Semantic vs presentation state

Keep these distinct.

Examples:

- `ReaderSelectionState` describes what is selected and is Core/domain state.
- `ReaderSelectionPresentation` describes where the selection toolbar is placed and is App presentation state.
- `ReaderPresentationState` owns logical presentation facts such as the real document title/zoom value instead of treating controls as data stores.
- native `PDFSelection`, `PDFAnnotation`, `PDFView`, `WKWebView`, and window-coordinate geometry remain renderer/platform concerns.

Do not use labels, fields, view identifiers, or view hierarchy order as authoritative application state.

### Feature state

The Reader Shell already partitions state into focused areas such as:

- document text;
- embedding;
- AI;
- vocabulary;
- notes;
- Read Aloud;
- search;
- reader-shell presentation/chrome.

New state should join the narrowest correct owner rather than expanding one giant general-purpose state object.

## 5. Native Reader Boundary

There are two renderer families:

```text
PDF
  -> PDFKit
  -> PDFKitReaderAdapter

EPUB / DOCX
  -> WebKit
  -> WebKitReaderAdapter
```

Shared reader intent is represented through typed App-layer capabilities.

### `ReaderContentBackend`

Shared capabilities such as:

- focus;
- clear selection;
- zoom.

### `ReaderPagedBackend`

PDF/paged capabilities such as:

- current page;
- page count;
- viewport anchor;
- go to page;
- scroll to page top;
- restore viewport anchor.

### `ReaderContinuousBackend`

Web/continuous-document capabilities such as:

- page-like scrolling;
- cover navigation;
- scrolling to reading progress.

Feature code should use these capabilities when the requested behavior is reader-level intent.

Renderer-specific implementation details stay in the adapters or another narrow platform service when they do not belong in the existing backend abstractions.

### Remaining direct native access

Some existing files still directly access `pdfView` or `webView`. The authoritative inventory is:

`scripts/reader_native_access_allowlist.txt`

This is migration debt, not a pattern to copy.

`scripts/check_reader_native_access.sh` rejects new unreviewed native access and rejects stale allowlist entries after access has been removed.

When changing an allowlisted area, migrate the native access behind an appropriate seam when that is naturally part of the work. Do not create forwarding abstractions that merely rename the coupling.

## 6. Cross-Format Feature Design

Product semantics should be defined before renderer mechanics.

If a feature is conceptually about a Document, selection, vocabulary, notes, AI context, navigation, or reading state, ask whether it applies to:

- PDF;
- EPUB/DOCX via the web reader.

Prefer:

```text
user intent
    -> shared feature operation
        -> renderer-specific mechanism when necessary
```

instead of separate unrelated PDF and Web features.

Current vocabulary Save/Remove behavior is an example: the product-level action is shared, while PDF and web-backed documents use different occurrence/location representations and storage mechanics.

Do not force renderer parity where the formats genuinely differ. Intentional differences should remain explicit and tested.

## 7. UI Technology

### SwiftUI

Prefer SwiftUI for ordinary declarative application UI where it preserves behavior and performance:

- settings/forms;
- lists;
- cards;
- simple chrome;
- focused presentation models.

### AppKit / native views

Keep native implementations where they solve a real interaction or performance problem.

Current intentional examples include:

- PDFKit document rendering;
- WebKit EPUB/DOCX rendering;
- rich Reading Note text editing;
- AI transcript rendering;
- window/responder-chain behavior;
- other native selection/text-system interactions.

There is no goal to eliminate AppKit or to move a hot path merely for stylistic consistency.

## 8. AI Architecture

AI conversation data must not depend on the rendered transcript hierarchy.

`AITranscriptModel` is the authoritative ordered transcript/focused-word model. AppKit views render from that state.

The current architecture intentionally keeps the transcript renderer AppKit while moving transcript semantics and policies into model code that can be tested without walking views.

Document-aware prompt requests use `DocumentAgentPromptCoordinator` for request identity, independent completion, auxiliary-task ownership, and cancellation. New async AI work should preserve per-request ownership rather than falling back to one ambiguous global task when multiple consumers are valid.

Looking up or defining a word and saving it are separate intents. Query flows may reuse existing saved data, but should not silently create user-owned records.

## 9. Reading Notes

Rich note editing intentionally remains AppKit because it relies on the native attributed-text editing system.

`ReadingNoteEditorModel` is the authoritative owner for the note/editor state around that native text surface, including:

- the current note;
- displayed text;
- dirty state;
- status state;
- favorite state;
- AI request identity/lifecycle.

The controller/view must not keep a second independently mutable note copy.

When extending Notes, keep rich-text/native mechanics at the UI edge and place independently testable state transitions in the model or domain layer.

## 10. Vocabulary

Vocabulary is split by responsibility rather than by one monolithic object.

Core owns reusable semantics such as:

- vocabulary text policy/normalization;
- language/lemma grouping rules where platform-independent;
- SRS behavior;
- persisted semantic record structures that belong to the domain;
- stable occurrence identity and dedup/save planning.

App owns document/rendering integration such as:

- PDF selection geometry and annotations;
- Web selection/location integration;
- application-specific stores/controllers;
- UI feedback and panels;
- asynchronous discovery/materialization tied to native documents.

`VocabularyOccurrenceSavePlanner` is the pattern for moving deterministic save rules out of PDFKit/controller code while keeping native geometry at the platform edge.

`saveCurrentVocabularySelection()` represents shared document-level Save intent and dispatches to PDF or web-backed implementation.

`ReaderWindowController+VocabularySaving.swift` is still large. Do not perform a size-only rewrite, but avoid adding new domain policy there when that policy can have a focused owner and tests.

## 11. Async and Concurrency Model

Swift 6 strict concurrency is the baseline.

UI/native state publication stays on the main actor.

Potentially expensive work should execute away from the UI path when appropriate, including:

- document parsing/extraction;
- filesystem work;
- database scans;
- network requests;
- embeddings/indexing;
- AI processing;
- expensive derived content.

Async work must retain enough identity to detect staleness.

Existing patterns include:

- document load generation;
- document ID checks;
- request IDs;
- task cancellation;
- lifecycle flags such as editor closing state.

A result from document A must not mutate document B after navigation. A slower request must not overwrite a newer request when only the newest result is valid.

High-frequency state changes should be coalesced, debounced, throttled, or kept local where broad observation would create unnecessary UI work.

## 12. Persistence

User-owned data compatibility is a higher priority than implementation convenience.

Before changing a persisted model/store:

1. identify the existing authoritative persistence path;
2. determine whether old data remains readable;
3. add migration/fallback behavior when necessary;
4. cover compatibility with tests;
5. update format documentation when the external/on-disk contract changes.

Do not create a second persistence path for the same concept because it is easier for one new feature.

Read/query actions should not gain incidental writes. Mutations should remain explicit except for already-established behaviors such as intentional note auto-save.

## 13. Performance

The repository already has substantial performance infrastructure under `docs/perf/`.

Important hot paths include:

- app launch;
- document visibly ready;
- PDF paging and scrolling;
- web scrolling;
- selection;
- search;
- vocabulary save/lookup;
- AI first response/streaming and long transcripts;
- large vocabulary/note collections;
- Read Aloud progress;
- resize/theme interaction.

Use existing instrumentation and baselines when a change can materially affect one of these paths.

Do not add architecture or framework indirection to a hot path merely for conceptual uniformity.

Do not add new performance infrastructure unless the existing tooling cannot measure a concrete risk.

## 14. Verification and Enforced Invariants

The main deterministic local gate is:

```sh
./scripts/check.sh --no-build
```

It currently covers, among other checks:

- whitespace/generated wiki consistency;
- UI theme coverage;
- Core portability;
- Core semantic ownership;
- reader native-access boundary;
- strict Swift 6 build with warnings as errors;
- SwiftPM tests;
- the regression harness;
- performance-capture validator tests.

GitHub Actions runs this deterministic suite on PRs and pushes to `main`.

Use:

```sh
./scripts/build_app.sh
```

when app assembly, resources, framework linkage, or UI behavior changes.

GUI smoke tests and representative/live performance capture remain environment-dependent and should be run when the task requires them.

A failing architecture check is normally a design signal. Do not weaken a check or expand an exclusion/allowlist simply to make a patch green.

## 15. Current Architectural Debt

These are known conditions, not invitations for broad cleanup:

### Native-reader access

Direct PDFKit/WebKit access still exists in the reviewed native-access allowlist.

Direction: shrink opportunistically as relevant feature slices gain typed capabilities.

### `ReaderWindowController`

The controller remains a large composition root with many feature extensions.

Direction: move new independently testable policy/workflow logic to focused owners during feature work; do not start another controller rewrite solely for size.

### Large feature files

Some mature areas, especially vocabulary persistence/saving, remain large.

Direction: extract only when the extraction removes real coupling, establishes state ownership, improves reuse, or creates meaningful testability.

The active historical migration record is `docs/plans/architecture-completion/`. It should not become a required per-feature workflow.

## 16. Adding a New Feature

For an ordinary Codex-driven feature, no separate spec/design/task documents are required unless the user asks for them.

Before implementation, answer these questions from repository evidence:

1. What existing feature/model/service/store/adapter owns the closest behavior?
2. Is this domain logic (`LeafReaderCore`) or presentation/platform logic (`LeafReaderApp`)?
3. What is the single authoritative owner of any new mutable state?
4. Is the behavior document-level, and therefore relevant to both PDF and web-backed documents?
5. Does it require native reader capability, and if so which existing seam should carry it?
6. Can async work become stale, and what identity/cancellation guard is required?
7. Does it change persisted user data or turn a read into a write?
8. Is it on a measured/hot path?
9. Which focused tests demonstrate the behavior and prevent regression?

Then implement the smallest coherent change that answers those questions without inventing a parallel architecture.
