# UI architecture migration — performance-first roadmap

## North star

The target architecture is:

**platform-neutral domain models and policies + focused observable UI models + declarative SwiftUI where it performs well + small AppKit adapters for specialised macOS behaviour.**

This architecture serves three goals:

1. Enable a full redesign of the macOS application.
2. Preserve or improve responsiveness, scrolling smoothness, launch speed, and memory usage.
3. Prepare a genuinely shared core for future iPad and iPhone applications.

The objective is **not** to remove AppKit. PDFKit, WebKit, rich-text editing, AI transcript rendering, window coordination, responder-chain behaviour, menus, and other desktop-specific mechanisms should remain AppKit-based whenever that produces the best result.

A migration is successful only when the resulting surface is at least as responsive and reliable as the previous implementation.

---

## Architectural layers

### `LeafReaderCore`

Contains code that requires neither AppKit nor SwiftUI:

* Document identity and locator types
* Reader selection semantics
* Reading-position state
* Session rules
* Vocabulary policies and SRS logic
* AI conversation and transcript domain logic
* Reading-note domain logic
* Parsers and format-independent transformations
* Store protocols
* Platform-neutral service protocols
* Validation and policy types

This target must compile without AppKit, SwiftUI, PDFKit, WebKit, or AVFoundation.

### `LeafReaderSharedUI`

Contains reusable SwiftUI-facing presentation code that can reasonably work on both macOS and iOS:

* Design tokens
* Small reusable components
* UI presentation models
* Shared formatting
* Platform-image display helpers
* Generic list, detail, and status components

Not every observable model belongs in the core. Models containing colours, button actions, presentation flags, or SwiftUI-specific state belong here or in the platform application.

### `LeafReaderMac`

Contains the macOS application and platform adapters:

* AppKit windows and controllers
* PDFKit reader adapter
* WKWebView reader adapter
* Rich-text note editor adapter
* AI transcript renderer
* Selectable text adapters
* macOS menus and responder-chain integration
* Open/save panels
* Local speech runtimes
* macOS-specific SwiftUI views
* Accessibility and window coordination

### Future `LeafReaderIOS`

Contains new mobile views and mobile-specific adapters over `LeafReaderCore`.

The iOS interface should not attempt to reproduce the Mac interaction model exactly. Selection, navigation, contextual actions, and panels should be designed for touch.

---

## Performance principles

### 1. Measure before replacing high-frequency UI

Low-frequency screens such as Settings, Shelf, Notes list, and Vocabulary Library are suitable SwiftUI migration candidates.

High-frequency surfaces require profiling before substantial changes:

* PDF and web reader surfaces
* AI transcript
* Streaming AI responses
* Read-aloud progress
* Text selection
* Floating contextual controls
* Large vocabulary lists
* Rich-text editing

A surface should not be migrated merely because a SwiftUI implementation is possible.

### 2. AppKit remains the default for specialised text and document rendering

Retain AppKit for:

* `PDFView`
* `WKWebView`
* The rich-text note editor
* The AI transcript renderer
* Free-range selectable attributed text
* Main-window and child-window coordination
* Menus and responder-chain behaviour

SwiftUI may own surrounding chrome and ordinary controls while AppKit owns specialised rendering and interaction surfaces.

### 3. Observation must remain narrow

Avoid one large observable object containing all application state.

Use focused models such as:

* `ReaderDocumentModel`
* `ReaderChromeModel`
* `ReaderPanelPresentationModel`
* `ReaderSearchModel`
* `AITranscriptModel`
* `AIStreamingModel`
* `ReadingNoteEditorModel`
* `ReadAloudPresentationModel`

A change to AI streaming state should not invalidate the entire reader window.

### 4. High-frequency events do not directly become broad UI state

Throttle or coalesce:

* Scroll position
* Zoom changes
* AI streaming chunks
* Read-aloud progress
* Window resizing
* Panel resizing
* Selection geometry
* Session persistence

Publish meaningful state changes rather than every raw callback.

### 5. Heavy work stays off the main actor

The main actor owns final presentation state and UI interaction only.

Run the following outside the main actor where safe:

* PDF metadata extraction
* File hashing
* Cover rendering preparation
* Markdown parsing and preprocessing
* Database queries
* Dictionary lookups
* Embedding generation
* Search indexing
* AI decoding and post-processing

### 6. Stable identity and cached rendering

Long lists and transcript content must use stable identities.

Cache expensive derived content:

* Rendered Markdown
* Attributed strings
* Cover thumbnails
* Source summaries
* Vocabulary row presentation
* Note previews

Do not rebuild expensive content because an unrelated status, button, or theme property changed.

### 7. Every major migration is performance-gated

Before and after each major phase, compare:

* Launch time
* Main-window creation time
* Document-open latency
* Time to first visible page
* Scroll smoothness
* Panel-open latency
* Selection-toolbar latency
* AI streaming CPU usage
* Memory use with a long conversation
* Memory use with a large vocabulary library
* Window-resize responsiveness

No significant regression should be accepted without an explicit reason.

---

## Completed work

Completed so far:

* Shelf migrated to SwiftUI
* Notes list migrated to SwiftUI
* Vocabulary Library list and detail migrated to SwiftUI
* Vocabulary review card migrated to SwiftUI
* Reader top-bar presentation partially migrated to SwiftUI
* Reader bottom bar migrated to SwiftUI
* AI panel chrome migrated to SwiftUI
* AI transcript data extracted into `AITranscriptModel`
* All five Settings pages migrated to SwiftUI
* `ReaderSelectionState` extracted
* `ReaderWebPresentation` extracted
* `ReaderReadingPosition` extracted
* `ReaderSearchCursor` extracted
* `ReadingNoteEditorModel` extracted
* Shared reader design tokens introduced
* Accessibility identifiers and UI smoke checks introduced

The top bar is visually migrated. Document title is now authoritative model state. Page, zoom, search, and cover presentation remain deliberately owned by their document/view adapters where those objects are the native source of truth; they should move only when a concrete duplicate-state bug or cross-platform consumer requires it.

The AI transcript renderer remains AppKit. Its domain state should continue moving into testable models, but view replacement is not part of the planned migration.

---

# Phase 0 — Establish enforceable module and performance boundaries

This phase should happen before more large view migrations.

## 0.1 Create a real `LeafReaderCore` target

**Status: complete.** The shipping build, custom test harness, portability check, and SwiftPM manifest all compile the platform-neutral core as a separate Swift 6 module.

Move already-clean types into it incrementally.

Initial candidates include:

* `ReaderSelectionState`
* `ReaderWebPresentation`
* `ReaderReadingPosition`
* `ReaderSearchCursor`
* AI transcript domain structures and policies
* Reading-note policies
* Vocabulary policies
* Document locators and identities
* Pure validation logic

Do not rely on filename filtering or source-code grep to determine whether a type is portable. The compiler should enforce the boundary.

## 0.2 Add target-based tests

**Status: complete.** `LeafReaderCoreTests` is a dedicated SwiftPM test target. The Architecture workflow runs it and the portability compiler gate on `macos-15` with Xcode 16.4 explicitly selected. The existing custom harness remains the broad compatibility suite while target-based XCTest is the authoritative module-boundary proof.

Create dedicated tests for `LeafReaderCore`.

The existing logic-test script may remain temporarily, but the new target becomes the authoritative portability proof.

## 0.3 Capture performance baselines

**Status: representative workflow complete; private capture pending.** The checked-in manifest validator, capture driver, sanitized fixture sidecar, and regression tests cover the complete PDF/EPUB/DOCX plus long-conversation, vocabulary, and notes workflow. The repository has no private representative documents, so an operator must still run the workflow locally before another large UI migration. Commit only aggregate measurements and sanitized fixture metadata, never private documents.

Add lightweight signposts or timing instrumentation for:

* Application launch
* Main-window creation
* PDF open
* EPUB/DOCX open
* First-page display
* Shelf open
* Notes open
* Vocabulary Library open
* AI panel expansion
* Selection-toolbar appearance
* AI first-token latency
* Long-conversation streaming
* Theme switch

Keep a repeatable fixture set:

* Small PDF
* Large PDF
* EPUB
* DOCX
* Long AI conversation
* Large vocabulary database
* Notes database with many entries

## 0.4 Fix UI smoke-test reliability

**Status: complete.** Failure, infrastructure failure, and intentional skip use distinct exit codes, and a skip first proves the app is still alive.

The smoke environment must be deterministic:

* Use a known interface language
* Open fixture documents
* Use isolated temporary application data where possible
* Avoid depending on the previously restored user session
* Use distinct exit codes for failure and intentional skip
* Never report a launch failure as an accessibility-permission skip

## 0.5 Define actor boundaries

**Status: Swift 6 adoption complete; diagnostic hardening continues.** Both the core and app compile in Swift 6 language mode, the shipping build uses that mode, and UI controllers/models state their main-actor ownership. Full Xcode validation still reports a bounded warning backlog at serialized legacy boundaries such as PDFKit values, networking completions, read-aloud closures, and the parallel German-lemma buffer; resolve these incrementally without moving blocking work onto the main actor.

UI-facing observable models should be main-actor isolated.

Platform and storage services should perform expensive work outside the main actor and publish compact results back to UI models.

---

# Phase 1 — Finish Notes editor state and migrate only its chrome

The rich-text editor remains AppKit.

## 1.1 Make `ReadingNoteEditorModel` authoritative

Remove the duplicate mutable `note` from `ReadingNotePanelController`.

The controller should obtain snapshots from the model rather than synchronize two copies manually.

## 1.2 Fix dirty-state semantics

Assigning the same editor text must not mark the note dirty.

Separate operations such as:

* User changed text
* Initial content loaded
* Content restored
* Content committed
* Render refreshed

Do not express all of them as a raw assignment with identical side effects.

## 1.3 Keep rich-text editing in AppKit

Retain AppKit for:

* Attributed-string editing
* Selection ranges
* Undo and redo
* Embedded images
* Markdown-rendered text
* Formatting commands
* Slash commands
* Floating action positioning
* First-responder behaviour

This is a permanent, acceptable adapter unless a future SwiftUI editor provides equivalent behaviour and performance.

## 1.4 Migrate surrounding chrome to SwiftUI

SwiftUI may own:

* Window header
* Metadata
* Word count
* Save state
* Favourite state
* Toolbar buttons
* Status line
* More menu trigger
* AI busy state

The AppKit editor adapter should expose only focused state and commands.

## 1.5 Avoid full editor rerendering during ordinary typing

Do not rebuild the complete attributed document on every keystroke.

Theme changes may require a controlled rerender, but ordinary typing and status updates should remain incremental.

## Proof

* Logic tests for the editor model
* Existing editing features preserved
* No duplicate note state
* No false dirty state after save
* Typing remains smooth in a long note
* Undo, redo, and selection behaviour remain unchanged

---

# Phase 2 — Complete the reader-state boundary

The goal is not to rewrite the document views. The goal is to stop using UI controls as application data.

## 2.1 Extract authoritative reader presentation state

Add model state only for facts that otherwise have duplicate mutable owners or that portable/domain consumers must read. The document title met that test and is complete. Do not mirror native PDFKit/WebKit state merely to satisfy an architectural checklist.

Potential future candidates, driven by an actual consumer or defect, include:

* Document title
* Cover presentation
* Current page
* Page count
* Zoom percentage
* Search query and result count
* Full-screen state
* Active document type
* Loading state
* Panel visibility
* AI panel width and collapsed state
* Read-aloud presentation state

AI, embedding, and read-aloud features must read document state from models, not from `titleLabel.stringValue`, page fields, or other controls.

## 2.2 Keep temporary AppKit control bridges

The existing page and zoom fields may remain AppKit while responder-chain behaviour is preserved.

When a portable presentation model is justified, they should bind to model state:

* The model supplies the displayed value.
* User editing produces a command.
* The backend validates and applies it.
* The model receives the resulting authoritative value.

The control itself is not the source of truth.

## 2.3 Introduce focused backend interfaces

Create small protocols rather than one oversized reader protocol.

Examples:

* `ReaderNavigationProviding`
* `ReaderSelectionProviding`
* `ReaderSearchProviding`
* `ReaderGeometryProviding`
* `ReaderZoomProviding`
* `ReaderProgressProviding`

Implement these through:

* `PDFKitReaderAdapter`
* `WebKitReaderAdapter`

Do not store PDF selection geometry in shared state. Ask the active backend for geometry on demand.

## 2.4 Separate semantic selection from presentation geometry

`ReaderSelectionState` should hold:

* Selected text
* Surrounding context
* Occurrence or locator information

A separate selection-presentation model should hold:

* Anchor rectangle
* Preferred toolbar edge
* Toolbar visibility

Geometry must be recalculated when needed.

## 2.5 Reduce direct platform-view access

Track direct usage of:

* `pdfView.currentSelection`
* `pdfView`
* `webView`
* UI labels as data sources

The number should decrease after adapters are introduced.

A direct-access ceiling is useful temporarily, but the long-term goal is that feature code asks interfaces rather than reaching into reader views.

## 2.6 Retire writable property proxies gradually

Controller proxies are migration scaffolding.

Rules:

* Do not add new broad writable proxies.
* Prefer named model operations.
* Prefer read-only projections.
* Reduce proxy count over time.
* New feature code receives only the models and services it needs.

## Performance rules

* Do not publish raw scrolling coordinates through SwiftUI.
* Throttle reading-progress updates.
* Query selection geometry only when showing or repositioning an overlay.
* Keep PDFKit and WebKit as long-lived instances.
* Avoid document reloads caused by ordinary SwiftUI state updates.

## Proof

* No domain feature reads text from UI labels
* PDF and web documents behave identically
* Smooth scrolling remains unchanged
* Window resizing remains smooth
* Selection-toolbar latency does not regress
* Session restoration remains correct

---

# Phase 3 — AI conversation architecture without renderer migration

The AI transcript renderer remains AppKit for performance and mature text-selection behaviour.

## 3.1 Keep domain state outside the view hierarchy

Continue moving into testable models:

* Conversation ordering
* Persistence rules
* Deletion grouping
* Source tracking
* Focused-word state
* Trimming policy
* Regeneration metadata
* Active-response identity

The renderer must not be the authoritative source of conversation data.

## 3.2 Separate active streaming state

A streaming response should update only the active response presentation rather than force a complete transcript reconstruction.

Use:

* Batched streaming updates
* A stable active response identity
* Cached rendered Markdown
* Incremental attributed-string updates
* Controlled transcript trimming
* Explicit scroll-following rules

## 3.3 Keep AppKit rendering incremental

Avoid rebuilding every transcript entry during:

* One streaming update
* Status changes
* Selection changes
* Panel resize
* Unrelated reader-state changes

Only the affected entry should be updated.

## 3.4 Keep transcript state and renderer synchronization one-directional

The model is authoritative.

The AppKit renderer:

* Creates views for new entries
* Updates the active entry
* Removes entries that leave the model
* Reports user actions and text selection
* Never invents conversation state by inspecting its subviews

## 3.5 Do not make transcript view migration a roadmap requirement

A future renderer experiment may be considered only when:

* There is a clear UX or maintenance benefit
* A feature flag allows direct comparison
* Profiling demonstrates equal or better performance
* Text selection and scrolling behaviour remain reliable

Until then, AppKit remains the intended implementation.

## Proof

* Conversation rules are unit-tested without AppKit
* The renderer does not define conversation ordering or persistence
* Streaming remains smooth
* Long conversations scroll smoothly
* Memory remains within the agreed baseline
* Text selection remains reliable

---

# Phase 4 — Remaining macOS screens and controls

Migrate based on UX value and technical suitability, not file size alone.

## Recommended order

1. Notes editor chrome
2. Vocabulary trainer shell
3. Read-aloud controls and status
4. AI panel chrome and surrounding layout
5. Search overlay
6. Remaining vocabulary panel chrome
7. Diagnostics and About surfaces
8. Less frequently used utility panels

## SwiftUI-preferred surfaces

Use SwiftUI for:

* Forms
* Settings
* Lists
* Cards
* Toolbars
* Status rows
* Empty states
* Search and filter controls
* Inspectors
* Static layouts
* Standard menus and buttons where behaviour is sufficient

## AppKit-preferred surfaces

Retain AppKit for:

* Document rendering
* Rich text
* AI transcript rendering
* Complicated text selection
* Window-level overlays
* Menu validation and responder-chain edge cases
* Platform file panels
* Highly specialised controls where SwiftUI introduces measurable regressions

## Responsive layout work

Reduce fixed geometry where appropriate:

* Use intrinsic control sizing
* Add compact modes
* Move low-priority actions into overflow menus
* Test long localised labels
* Test narrow windows
* Preserve keyboard operation
* Avoid layout recomputation during document scrolling

---

# Phase 5 — Portable repositories and services

Observable UI models should not directly depend on global static stores when the state is intended to be portable.

Introduce protocols where useful:

* `AISettingsRepository`
* `ReaderSessionRepository`
* `VocabularyRepository`
* `ReadingNotesRepository`
* `CoverProviding`
* `SpeechSettingsRepository`

Do not introduce protocols solely for abstraction. Add them where they establish a real platform, persistence, or testing boundary.

For example:

* `ShelfModel` should receive a cover provider rather than own a concrete macOS singleton.
* Settings models may receive repository snapshots and emit changes rather than call global stores directly.
* Platform adapters should convert between core data and AppKit or UIKit types.

## Performance rules

* Prefer coarse repository operations over many small calls.
* Cache frequently reused immutable data.
* Avoid protocol-driven callback chains in per-frame or per-scroll hot paths.
* Concrete platform adapters may be used internally where profiling shows that abstraction adds avoidable complexity.

---

# Phase 6 — iPad and iPhone applications

This phase begins only after an iOS SDK is available.

Do not write unverified iOS-specific code in advance.

## Shared code

Reuse:

* Domain models
* Policies
* Parsers
* Repository protocols
* Session logic
* Vocabulary logic
* AI conversation logic
* Notes logic
* Suitable design tokens
* Suitable shared SwiftUI components

## Platform-specific code

Implement separately:

* File access and document security scope
* PDF presentation
* Web-document presentation
* Selection interaction
* Context menus
* Window and scene management
* Keyboard behaviour
* Touch navigation
* Speech engines
* Mobile storage integration

The mobile interface should optimize for touch and smaller screens rather than copying the Mac layout.

---

# Standing engineering practice

## Extract before creating a second implementation

When macOS and iOS need the same rule, extract the rule before implementing the second UI.

Do not copy logic between platform views.

## Distinguish type categories

Every new type should clearly be one of:

* Core domain model
* UI presentation model
* Platform adapter
* Service
* Repository
* View
* Coordinator

Do not assume every `@Observable` type is part of the portable core.

## Keep callback ownership clear

Action closures are acceptable for small UI models, but long callback lists indicate that the feature may need a dedicated action router or coordinator.

## Preserve existing behaviour during structural migrations

Do not combine:

* State extraction
* Major UX redesign
* Storage migration
* Rendering-engine changes

in one step unless required.

First establish the boundary, then redesign over it.

## Build and test each major split

After each meaningful architectural change:

* Build the application
* Run core tests
* Run feature logic tests
* Run deterministic UI smoke tests
* Perform a real reading session
* Compare performance baselines

## Profile high-risk changes

Use profiling for:

* Large SwiftUI lists
* Markdown rendering
* Reader resizing
* Theme switching
* Cover loading
* Document opening
* Read-aloud progress
* Selection overlays
* AI streaming and transcript rendering

Do not optimize ordinary low-frequency code speculatively.

---

# Definition of completion

The migration is complete when:

1. `LeafReaderCore` compiles without AppKit or SwiftUI.
2. No domain feature reads authoritative data from a view.
3. PDFKit, WebKit, rich-text, and transcript-rendering types are confined to adapters and platform coordination.
4. Each mutable state has one authoritative owner.
5. High-frequency events are throttled or locally contained.
6. Observable models are small enough that unrelated UI does not invalidate.
7. Writable controller proxies are substantially removed.
8. Direct PDFKit and WebKit access outside adapters is exceptional and documented.
9. AI transcript domain state is model-driven while its AppKit renderer remains incremental and performant.
10. UI tests use deterministic fixture state.
11. Launch and infrastructure failures cannot be reported as skipped tests.
12. No migration phase produces a significant unexplained performance regression.
13. AppKit remains wherever it offers better performance or native macOS behaviour.
14. A future iOS target can depend on `LeafReaderCore` without importing macOS frameworks.

---

# Immediate next actions

1. **Complete:** `LeafReaderCoreTests` is CI-owned on a pinned macOS/Xcode runner.
2. **Complete:** `LeafReaderApp` and the shipping build use Swift 6 language mode; remaining strict-concurrency warnings form an explicit follow-up queue.
3. **Operator checkpoint:** run the private representative performance workflow with real PDF, EPUB, DOCX, long-conversation, notes, and vocabulary fixtures; commit aggregate results and sanitized metadata only.
4. **Complete:** EPUB/DOCX vocabulary records now have stable vocabulary identity plus lemma/surface metadata, with additive SQLite migration and legacy repair tests.
5. **Complete:** the versioned user-data backup service validates its allow-listed package, hashes, plist, and SQLite integrity, then restores with staged replacements and reverse-order rollback. See `docs/BACKUP_FORMAT.md`.
6. **Validation:** portability, target XCTest, the custom regression harness, and build/sign pass under full Xcode 16.2. UI smoke and the private performance capture remain machine/operator gates before discretionary UI migration resumes.

This version treats the AI transcript’s AppKit renderer as an intentional permanent component rather than an incomplete migration.
