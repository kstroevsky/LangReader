# Architecture Completion Design

## Ownership

- Core owns document, selection, vocabulary/SRS, reading-note, AI-conversation, parsing, persistence-format, and algorithmic semantics.
- App owns presentation state, localized view models, accessibility/control descriptions, window geometry, native readers, and feature coordination.
- `ReaderWindowController` remains the composition root and routes user intent; workflow state and policy belong to focused coordinators or services.

## Native Reader Boundary

Capabilities are introduced only with a production consumer. Protocols use semantic values and typed events; they do not expose `PDFView`, `WKWebView`, `PDFSelection`, `PDFAnnotation`, raw JavaScript, or `Any` payloads.

Migration order is loading/navigation/viewport, search/selection, persistent marks, AI sources, read-aloud focus, then remaining theme/layout/lifecycle access. Each slice preserves document-generation and cancellation guards.

## Workflow Extractions

- `VocabularyOccurrenceSavePlanner` owns stable occurrence identity, duplicate suppression, and the distinction between found and newly inserted records. The persisted record is a Core model; PDF selection geometry and the paced discovery loop stay in the App until a native document service can replace them without hiding `PDFDocument` in closures.
- `DocumentAgentPromptCoordinator` owns request identity, continuations, auxiliary retrieval tasks, completion, and independent cancellation. Retrieval/index services and evidence rendering remain separate collaborators rather than being pulled into a large replacement object.

These types are created only when their dependencies can be expressed without native views or UI panels.

## Implemented Native Capabilities

`ReaderContentBackend` owns focus and zoom. `ReaderPagedBackend` additionally owns page navigation, page-top placement, and typed viewport anchors. `ReaderContinuousBackend` owns semantic page scrolling, cover navigation, and progress restoration. These capabilities removed raw PDF destinations and WebKit scroll scripts from reader navigation while keeping renderer details in the adapters.

## Compatibility

Codable shapes, database schemas, bookmarks, note locators, vocabulary identifiers, accessibility identifiers, command behavior, and performance thresholds do not change. Incidental product defects are recorded separately rather than fixed during this migration.
