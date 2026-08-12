# LeafReader Development Contract

These instructions apply to every change in this repository. Preserve user-owned work and keep changes scoped to the requested behavior.

## Start With Repository Evidence

- If `.codegraph/` exists, use `codegraph explore` before text search or broad file reading when locating code, tracing ownership, or estimating blast radius.
- Read the relevant manifest, checks, tests, and nearby feature documentation before editing.
- Do not start a broad cleanup or refactor because a controller or file is large. Make the smallest coherent change that improves the requested behavior.

## Module Placement Is An Architectural Decision

`LeafReaderCore` is the domain/core module, not a collection of everything that happens to compile without AppKit.

Put in `LeafReaderCore`:

- document, vocabulary/SRS, AI-conversation, and reading-note semantics;
- parsing, persistence formats, algorithms, and domain policies;
- cross-platform protocols that express domain capabilities;
- state whose meaning does not depend on a window, control, layout, or rendering framework.

Keep in `LeafReaderApp`:

- macOS AppKit and SwiftUI presentation;
- presentation state and presentation models, including toolbar/button descriptors, ordering, accessibility identifiers, formatting, and design tokens;
- PDFKit, WebKit, `NSTextView`, window-coordinate geometry, and concrete platform services;
- application composition and feature coordination.

Framework-free is necessary for Core, but it is not sufficient. A type named or documented in terms of presentation, chrome, toolbars, controls, accessibility identifiers, layout, or window coordinates normally belongs in `LeafReaderApp` even if it imports only Foundation.

`scripts/core_portable_files.txt` is a portability probe for framework-free app code. It is not a promotion queue for `LeafReaderCore`.

Do not create a `LeafReaderSharedUI` target until iOS work actually begins. Until then, reusable presentation code remains in `LeafReaderApp/SharedUI` or its owning app feature.

State must have one authoritative owner. UI projections may expose state read-only or send intents back to that owner; do not introduce a second mutable copy for convenience.

## Native Reader Boundary

PDFKit and WebKit remain the native rendering engines, but feature intent should pass through `ReaderContentBackend`, a more specific existing adapter, or a narrow platform service.

- Never add a file to `scripts/reader_native_access_allowlist.txt` merely to make the check pass.
- New PDFKit/WebKit behavior should extend an existing adapter or introduce a narrow platform service.
- Expanding the allowlist requires explicit architectural justification in the task or review description.
- When substantially changing an allowlisted file, move direct `pdfView`/`webView` access behind a seam when that is reasonably part of the change, then remove the stale entry.
- Do not replace direct access with an untyped closure or a generic escape hatch that merely hides the same coupling.

The allowlist is migration debt. Its permitted long-term direction is downward.

## Reader Window Ownership

`ReaderWindowController` is the macOS composition root and may coordinate features, route user actions, and own native view lifetimes. It must not become the owner of new domain rules.

Keep controller methods short and intent-oriented. Put normalization, deduplication, persistence policy, scheduling, parsing, and other feature rules in the owning model, coordinator, service, or Core policy. Thin the controller opportunistically while implementing features; do not launch a controller rewrite solely because it is large.

## Feature Workflow

Before implementing a behavior-changing or multi-file feature, make these three things explicit in the working plan or a durable design document:

1. **Spec** — user-visible behavior, non-goals, acceptance criteria, and important edge/failure cases.
2. **Design** — state owner, module placement, data/control flow, native-reader seams, persistence or migration effects, and performance/security risks.
3. **Tasks** — dependency-ordered, independently verifiable slices, including tests and final validation.

A small isolated fix may express all three compactly. For larger or review-sensitive work, add a checked-in document under `docs/plans/<feature>/` with `spec.md`, `design.md`, and `tasks.md`; keep it updated when implementation changes the design. Do not let a task list substitute for acceptance criteria or ownership decisions.

## Verification Contract

- Run the narrowest affected tests while iterating.
- For code changes, run `./scripts/check.sh --no-build` before handoff when the environment permits. It is the deterministic CI-equivalent suite.
- Run `./scripts/build_app.sh` when app assembly, resources, framework linkage, or UI behavior changes.
- Run GUI smoke checks only in a logged-in session with the required Accessibility permission.
- Use the existing performance capture tools when a change can materially affect launch, document readiness, paging/scrolling, search, long AI transcripts, large notes collections, or large vocabulary datasets.
- Do not add new performance infrastructure without a concrete measurement gap.
- Do not weaken a check, add an exclusion, or expand an allowlist as a substitute for fixing the violation.

Swift builds and tests must remain in Swift 6 mode and pass with warnings treated as errors.
