# LeafReader Development Contract

These instructions apply to every change in this repository. Preserve user-owned work, follow the current architecture, and keep changes scoped to the requested behavior.

## Start With Repository Evidence

For non-trivial changes:

1. Read `CONTEXT.md` for canonical product/domain terminology.
2. Read `docs/architecture/DESIGN.md` for current architecture and ownership.
3. If `.codegraph/` exists, use `codegraph explore` before broad text search/file reading when locating code, tracing ownership, or estimating blast radius.
4. Read the relevant manifest, checks, tests, nearby feature documentation, and existing implementation before editing.
5. Use `docs/wiki/code-map.md` as generated navigation only, not as architecture authority.
6. If the task changes the Core boundary, native-reader boundary, or the ongoing architecture migration, also inspect `docs/plans/architecture-completion/`.

Prefer extending an existing model, service, store, coordinator, capability, or adapter over creating a parallel system.

Do not start unrelated cleanup or a broad refactor because a controller/file is large. Make the smallest coherent change that satisfies the requested behavior.

## Architectural Invariants

`LeafReaderCore` owns domain/shared semantics: document and selection semantics, vocabulary/SRS rules, reading-note and AI-conversation semantics, parsing, persistence formats, algorithms, and domain policies.

`LeafReaderApp` owns macOS presentation/platform integration: AppKit/SwiftUI, PDFKit/WebKit, presentation state/models, accessibility/control descriptions, window geometry, native services, composition, and feature coordination.

Framework-free is necessary for Core but is not sufficient. `scripts/core_portable_files.txt` is a portability probe for framework-free App code; it is not a promotion queue for `LeafReaderCore`.

Do not create `LeafReaderSharedUI` until a real second platform requires it.

Every mutable fact must have one authoritative owner. UI projections may expose state read-only or send intents back to that owner; views/labels/control contents must not become canonical application data.

Semantic state must stay separate from transient presentation geometry and native renderer objects.

Existing broad forwarding properties on `ReaderWindowController` are compatibility seams, not a preferred API. Do not grow new read/write proxy surfaces merely for convenience.

## Native Reader Boundary

PDF uses PDFKit. EPUB/DOCX use the WebKit reader path.

Feature intent should pass through `ReaderContentBackend`, `ReaderPagedBackend`, `ReaderContinuousBackend`, another existing adapter, or a narrow typed platform service.

- Do not add new direct `pdfView` / `webView` access in ordinary feature code.
- Never add a file to `scripts/reader_native_access_allowlist.txt` merely to make the check pass.
- Expanding the allowlist requires explicit architectural justification in the task/review.
- When substantially changing an allowlisted file, move direct native access behind a seam when that is reasonably part of the change, then remove the stale entry.
- Do not hide native coupling behind `Any`, untyped closures, raw native-object escape hatches, or generic wrappers.

The allowlist is migration debt. Its long-term direction is downward.

For Document-level behavior, check both reader families. Prefer one product-level intent with renderer-specific mechanisms underneath it; do not accidentally make a feature PDF-only because the first implementation uses PDFKit.

## Reader Window Ownership

`ReaderWindowController` is the macOS composition root. It may own native view lifetimes, implement delegates, route user actions, and connect feature state/services/adapters.

Keep controller methods short and intent-oriented. New normalization, deduplication, SRS rules, persistence policy, scheduling, parsing, request lifecycle, and other independently testable feature rules belong in the owning model, coordinator, service, store, or Core policy.

Thin the controller opportunistically while implementing features; do not launch another controller rewrite solely because it is large.

## UI, Async, Persistence, and Performance

LeafReader is intentionally a SwiftUI + AppKit hybrid. Use SwiftUI for ordinary declarative UI when it preserves behavior and performance. Keep native/AppKit implementations where they are intentionally better suited, including current PDFKit/WebKit rendering, rich-note editing, AI transcript rendering, and responder/window-specific behavior.

UI/native interaction belongs on the main actor. Expensive filesystem, parsing, database, network, embedding, AI, indexing, and similar work must not unnecessarily block it.

Async work that can outlive its originating state must validate the relevant document/load generation, document ID, request ID, cancellation token, or lifecycle state before applying results. Late work must not mutate a newer document/request or a closed owner.

Preserve persisted user data and reuse the existing persistence path for each domain concept. Persisted-shape/schema changes require compatibility/migration consideration and regression coverage.

Read/query operations must not silently acquire unrelated write side effects. Saving/removing/favoriting/deleting/importing must remain explicit unless existing behavior intentionally auto-saves.

Protect established hot paths such as launch/document readiness, scrolling/paging, selection, search, vocabulary lookup/save, AI streaming, Read Aloud, large collections, resize, and theme changes. Use existing `docs/perf/` tooling when a change can materially affect them. Do not claim performance improvement without measurement or add new performance infrastructure without a concrete measurement gap.

## Feature Workflow

For a behavior-changing or multi-file feature, make these explicit in the working plan before implementation; checked-in plan files are not required for ordinary Codex tasks:

1. **Behavior** — requested outcome, non-goals, acceptance criteria, and important edge/failure cases.
2. **Design** — existing owner/pattern being extended, state owner, module placement, data/control flow, reader seam, persistence/async/performance implications.
3. **Steps** — dependency-ordered, independently verifiable implementation slices including tests and final validation.

A small isolated fix may express all three compactly.

Create durable files under `docs/plans/<feature>/` only when the user asks for them or when the change is architecture-/migration-/review-sensitive enough that the design needs to outlive the task.

Do not let an implementation checklist substitute for acceptance criteria or ownership decisions.

## Verification Contract

- Run the narrowest affected tests while iterating.
- Add a deterministic regression test for bugs when practical.
- Cover shared PDF/Web behavior in both reader families when relevant.
- For code changes, run `./scripts/check.sh --no-build` before handoff when the environment permits; it is the deterministic CI-equivalent suite.
- Run `./scripts/build_app.sh` when app assembly, resources, framework linkage, or UI behavior changes.
- Run GUI smoke checks only in a logged-in session with the required Accessibility permission.
- Use existing performance capture tools when the task can materially affect a measured hot path.
- Do not weaken a check, add an exclusion, or expand an allowlist as a substitute for fixing the violation.

Swift builds and tests must remain in Swift 6 mode and pass with warnings treated as errors.

## Handoff

Report:

- what behavior changed;
- important ownership/architecture choices;
- tests/checks run;
- performance impact if measured;
- any real remaining limitation.

If the implementation requires materially changing an established architecture rule, call that out explicitly instead of silently redefining the rule in code.
