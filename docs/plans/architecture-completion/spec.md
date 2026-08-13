# Architecture Completion Spec

## Goal

Complete the remaining module and native-reader boundary work through behavior-preserving vertical slices. Every slice must remove measurable architectural debt, establish an independently testable seam, or enforce an invariant.

## Acceptance Criteria

- Presentation-only state and formatting no longer live in `LeafReaderCore`.
- Feature code uses typed reader capabilities instead of gaining new direct `PDFView` or `WKWebView` access.
- The native-access allowlist only shrinks; every migrated file is removed immediately.
- Vocabulary saving and document-agent requests gain independently testable workflow owners before controller logic is removed.
- Deterministic CI rejects new Core presentation types and new unauthorized native-reader access.
- Swift 6 strict builds, tests, persisted data formats, accessibility identifiers, toolbar order, keyboard behavior, and visible UI behavior remain unchanged.

## Non-Goals

- No `LeafReaderSharedUI` or iOS target.
- No UI redesign, persistence migration, or new performance infrastructure.
- No controller extraction based only on file size.
- No generic native-object or raw-JavaScript escape hatch.
