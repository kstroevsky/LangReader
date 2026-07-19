# Architecture

Leaf Reader is a native macOS reader built with Swift, AppKit, PDFKit, WebKit, and Sparkle. The source tree is organized by product feature so a change begins in the feature directory rather than a flat list of controller extensions.

## Source Tree

```text
Sources/LeafReaderApp/
  App/                 application lifecycle, menus, diagnostics, updates
  ReaderShell/         reader window, chrome, shelf, selection, sessions
  DocumentReading/     document sessions, import, PDF, EPUB, DOCX, WebKit
  AIConversation/      chat, prompts, retrieval, embedding cache
  VocabularyReview/    dictionary lookup, records, review, export
  ReadingNotes/        notes, editor, panel, persistence
  ReadAloud/           playback coordination, text batching, reader controls
  Settings/            AI, embedding, speech, and appearance settings
  Platform/            networking, persistence, and speech runtime adapters
  SharedUI/            reusable AppKit and Markdown presentation code
  Support/             small cross-cutting utilities
  Resources/           bundled scripts, prompts, dictionaries, and manifests
```

## Runtime Flow

```text
App
  -> Reader Shell
     -> Document Session
        -> PDFKit or WebKit presentation
     -> AI Conversation / Vocabulary Review / Reading Notes / Read Aloud
        -> Platform services and persistent stores
```

`DocumentSession` owns the active document identity, load generation, restoration data, and teardown. `DocumentPresentationState` owns transient presentation details such as the table of contents and crop state. The Reader Shell owns the window and routes user input to the feature that owns the behavior.

`SpeechSynthesisRuntime` is the single policy and dispatch seam between Read Aloud and concrete local speech engines. Networking and SQLite helpers live under `Platform` so feature code does not need to know their implementation details.

## Navigation Rules

- Start in the feature directory named by the user-visible behavior.
- Use `ReaderWindowController` extensions as feature entry points, not as forwarding coordinators.
- Keep lifecycle state in its owning model (`DocumentSession`, review session, or note/editor state) rather than in the window shell.
- Place reusable UI in `SharedUI`; place service adapters in `Platform`.
- Keep tests alongside the feature under `Tests/LeafReaderTests/` and run them with `scripts/run_tests.sh`.

## High-Leverage Files

- `Sources/LeafReaderApp/ReaderShell/ReaderWindowController.swift`
- `Sources/LeafReaderApp/DocumentReading/DocumentSession.swift`
- `Sources/LeafReaderApp/AIConversation/AIChatPanel.swift`
- `Sources/LeafReaderApp/ReadAloud/SpeechSynthesisRuntime.swift`
- `Sources/LeafReaderApp/Platform/SpeechRuntime/SpeechRuntimeResourceManager.swift`
- `Sources/LeafReaderApp/VocabularyReview/WordRecordSQLiteStore.swift`
