# LangReader Feature Development Specification

## Purpose

Every non-trivial LangReader feature must be implemented as a behavior-driven vertical slice that preserves the repository's architectural boundaries.

The objective is not merely to make the requested UI or behavior work. The implementation must leave state ownership, module boundaries, lifecycle behavior, persistence compatibility, performance characteristics, and native-reader boundaries at least as clear as they were before the change.

## Authority

When instructions conflict, use this order:

1. `AGENTS.md` — repository-wide architectural and engineering invariants.
2. `CONTEXT.md` — canonical domain terminology and concepts.
3. `docs/wiki/architecture.md` — current system structure and ownership.
4. Global design-system specification — presentation and interaction invariants.
5. Feature `spec.md` — required user behavior.
6. Feature `design.md` — approved technical approach.
7. Feature `tasks.md` — implementation sequence.
8. Existing code — evidence about the current system, including known migration debt; existing patterns are not automatically desirable.

Do not copy a known legacy pattern merely because similar code already exists.

## Change Classification

A trivial isolated correction may be implemented with a compact in-task specification.

Create a durable feature directory under `docs/plans/<feature>/` when a change:

* changes user-visible behavior;
* touches multiple feature areas;
* creates or changes persisted data;
* changes state ownership;
* introduces an asynchronous workflow;
* changes PDFKit/WebKit integration;
* changes a public or cross-feature interface;
* has meaningful performance implications;
* materially redesigns a screen or interaction.

A feature directory contains:

* `spec.md`
* `design.md`
* `tasks.md`

Large initiatives use a roadmap containing independently implementable feature specs rather than one giant implementation plan.

---

## Phase 0 — Repository Evidence

Before proposing implementation:

1. Read `AGENTS.md`.
2. Read relevant terminology in `CONTEXT.md`.
3. Read the relevant section of `docs/wiki/architecture.md`.
4. Locate the current state owner, persistence owner, native renderer boundary, and tests.
5. Inspect existing implementations before creating new abstractions.
6. Identify known migration debt in the touched area.
7. State what must remain unchanged.

Do not begin implementation while ownership is still ambiguous.

---

## Phase 1 — Feature Specification

`spec.md` describes **what and why**, not implementation mechanics.

It must contain:

### Problem

What user problem or workflow is being improved?

### User-visible behavior

Describe the expected behavior from the user's perspective.

### Scope

Explicitly state what is included.

### Non-goals

Explicitly state adjacent behavior that must not change.

### User scenarios

Describe the important successful workflows.

### State matrix

For every relevant surface, specify:

* empty;
* normal;
* loading;
* partial;
* disabled;
* error;
* offline/unavailable where applicable;
* cancellation;
* recovery;
* restored-session state.

### Input and interaction

Specify where applicable:

* mouse;
* keyboard;
* contextual actions;
* selection;
* focus;
* hover;
* drag/drop;
* window resizing;
* accessibility interactions.

### Document-format behavior

Explicitly state whether behavior applies to:

* PDF;
* EPUB;
* DOCX;
* all formats;
* only a subset.

Differences between formats must be deliberate.

### Persistence expectations

State whether the feature:

* persists nothing;
* modifies existing persisted data;
* introduces persisted data;
* requires migration;
* must remain backward-compatible.

### Performance expectations

State realistic scale assumptions and any interaction that must remain immediate.

Examples:

* large PDF;
* long EPUB/DOCX;
* thousands of Vocabulary Records;
* long AI Conversation;
* large Reading Note collection.

### Acceptance criteria

Acceptance criteria must be externally observable or independently testable.

Avoid criteria such as “code is clean.”

Prefer criteria such as:

* reopening the document restores X;
* cancelling operation Y prevents stale result Z;
* changing theme updates surfaces A/B/C;
* no new direct PDFView/WKWebView access is introduced;
* operation remains below the established performance threshold.

### Open questions

Unresolved questions must be resolved before implementation if they could change architecture, persistence, UX, or acceptance criteria.

---

## Phase 2 — Technical Design

`design.md` explains **how the feature fits into the existing system**.

It must contain:

### Existing system

Identify relevant:

* modules;
* state owners;
* coordinators;
* native-reader adapters;
* persistence services;
* tests;
* known architectural debt.

### State ownership

For every mutable state introduced or changed:

* name its authoritative owner;
* describe its lifecycle;
* describe how views observe it;
* describe how user intent changes it.

There must not be two authoritative mutable copies of the same state.

Derived or presentation values may be cached only when invalidation is explicit.

### Module placement

For every significant new type, identify its intended module.

`LeafReaderCore` owns product semantics, algorithms, persistence formats, and domain policy.

`LeafReaderApp` owns presentation, macOS coordination, AppKit/SwiftUI, PDFKit/WebKit, window geometry, concrete services, and design-system presentation.

“Can compile without AppKit” is not sufficient reason to place something in Core.

### UI boundary

Views render state and emit intent.

Views must not become owners of:

* persistence policy;
* normalization/deduplication rules;
* document parsing;
* scheduling policy;
* network orchestration;
* AI request lifecycle;
* database transactions.

A view may render immutable Core values but must not acquire concrete stores or native document engines merely for convenience.

### Native reader boundary

New feature behavior must use a typed reader capability or narrow platform service when interacting with PDFKit/WebKit.

Do not expose through a new protocol:

* `PDFView`;
* `WKWebView`;
* `PDFSelection`;
* `PDFAnnotation`;
* raw JavaScript strings;
* `Any`;
* generic closures whose purpose is merely to hide native access.

Existing allowlisted access may remain when unrelated to the feature.

Touched allowlisted code must be examined for an opportunity to move the relevant behavior behind a semantic seam.

The allowlist must never grow as an implementation shortcut.

### Concurrency and lifecycle

For every asynchronous operation identify:

* initiating owner;
* actor/isolation;
* task owner;
* cancellation path;
* stale-result protection;
* document/session generation requirements;
* cleanup on close/unload/replacement.

Heavy parsing, indexing, embedding, persistence, Markdown transformation, hashing, and similar work must not be moved to the main actor merely because the consumer is UI.

Only compact presentation state should cross back to the main actor.

### Persistence

Document:

* schema changes;
* serialization changes;
* stable IDs;
* migrations;
* backward compatibility;
* failure and recovery behavior.

Persistence changes require explicit acceptance criteria and migration tests.

### Performance

Describe:

* expected complexity;
* hot paths;
* high-frequency events;
* caches;
* invalidation;
* batching/throttling/debouncing;
* main-thread work;
* large-data behavior.

Do not publish raw high-frequency renderer state to broad observable models.

Long-lived expensive native views must not be recreated because an unrelated SwiftUI state value changed.

### Security and privacy

Identify changes affecting:

* local documents;
* API keys;
* AI providers;
* network requests;
* local speech runtimes;
* exported data;
* filesystem access.

### Alternatives considered

Record alternatives that would materially change ownership or complexity.

Explain why the selected approach is the simplest one that satisfies the feature.

### Architecture delta

Explicitly state:

* new types;
* removed types;
* changed ownership;
* new dependencies;
* new abstractions;
* changed allowlists/exceptions;
* architectural debt removed;
* architectural debt intentionally retained.

“No architectural change” is a valid answer.

---

## Phase 3 — Architecture Review

Before implementation, review `spec.md` and `design.md` together.

Implementation must not begin with unresolved answers to:

1. Who owns the mutable state?
2. Which module owns the rules?
3. Which object owns asynchronous lifetime and cancellation?
4. How does the feature reach PDFKit/WebKit, if necessary?
5. Does persistence change?
6. What are the performance-sensitive paths?
7. How is the behavior independently tested?
8. Does the design introduce a second source of truth?
9. Does it create an abstraction without a concrete need?
10. Does it expand known migration debt?

Every acceptance criterion must have a corresponding design path.

Every material design element must correspond to a requirement or architectural necessity.

---

## Phase 4 — Tasks

`tasks.md` must be dependency ordered and composed of independently verifiable vertical slices.

Prefer:

1. domain/state contract;
2. focused tests;
3. service/coordinator or native seam;
4. presentation integration;
5. persistence/migration if required;
6. end-to-end validation;
7. architecture/performance validation.

Avoid tasks such as:

* “refactor ReaderWindowController”;
* “clean up architecture”;
* “create reusable abstraction”;

unless there is an explicit measurable outcome.

Each task should state:

* behavior/design requirement it satisfies;
* files or area expected to change;
* test or verification proving completion.

---

## Phase 5 — Implementation

During implementation:

* keep changes scoped;
* implement one verifiable slice at a time;
* run the narrowest relevant tests after each slice;
* update `design.md` when implementation discovers a materially different architecture;
* update `spec.md` first if intended behavior changes;
* never silently change the contract to match accidental implementation.

Do not weaken checks or add exceptions to complete a task.

---

## Phase 6 — Verification

Run the repository-prescribed checks from `AGENTS.md`.

Additionally validate the feature against its own acceptance criteria.

Performance-sensitive changes must use the existing measurement tools when they can materially affect established hot paths.

UI changes must verify the actual rendered result and relevant interaction states rather than treating compilation as visual validation.

---

## Phase 7 — Convergence Review

After implementation, compare the **actual diff and behavior** against:

* `spec.md`;
* `design.md`;
* `tasks.md`;
* `AGENTS.md`.

Check for:

* requirements not implemented;
* unintended behavior;
* architectural drift;
* new duplicate state;
* accidental native-reader access;
* persistence incompatibility;
* unplanned dependencies;
* unnecessary abstractions;
* missing tests;
* unfinished temporary compatibility code.

If a gap exists, add a concrete task and resolve it before declaring the feature complete.

---

## Definition of Done

A feature is complete only when:

* acceptance criteria are satisfied;
* state has one authoritative owner;
* module placement follows repository semantics;
* async work has explicit lifetime and stale-result protection;
* no unjustified architecture exception was introduced;
* persistence compatibility is proven where relevant;
* affected tests pass;
* repository checks pass;
* performance-sensitive behavior has been validated when applicable;
* UI behavior has been visually and interactively checked when applicable;
* spec/design/tasks reflect the implementation that actually shipped.

The implementation report must summarize:

* user-visible result;
* architecture/state ownership;
* tests run;
* performance validation;
* architectural debt added or removed;
* any deliberately deferred work.
