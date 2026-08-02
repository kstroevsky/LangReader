# Architecture

Leaf Reader is a native macOS reader built with Swift, AppKit, SwiftUI, PDFKit, WebKit, and Sparkle. The shipping application is split into a platform-neutral `LeafReaderCore` module and a macOS `LeafReaderApp` module.

## Source Tree

```text
Sources/LeafReaderCore/
  AIConversation/      prompts, response formatting, conversation data, embedding storage
  DocumentReading/     document decoding, identity, selection, and presentation policies
  Platform/            portable persistence and local-runtime infrastructure
  ReadAloud/           speech text, matching, and keyboard policies
  ReaderShell/         portable reader state
  ReadingNotes/        note models, persistence, Markdown, assets, and export
  SharedUI/            platform-neutral display policies
  VocabularyReview/    dictionary, vocabulary, review, statistics, and export

Sources/LeafReaderApp/
  App/                 application lifecycle, menus, diagnostics, updates
  ReaderShell/         reader window, chrome, shelf, selection, sessions
  DocumentReading/     document sessions plus PDFKit and WebKit adapters
  AIConversation/      chat UI, requests, retrieval integration, and source annotations
  VocabularyReview/    vocabulary UI, document integration, and SQLite record storage
  ReadingNotes/        note editor, panels, and document integration
  ReadAloud/           playback coordination, synthesis adapters, and reader controls
  Settings/            AI, embedding, speech, and appearance settings
  Platform/            macOS networking, persistence, and speech runtime adapters
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

`DocumentSession` owns the active document identity, load generation, restoration data, and teardown. `DocumentPresentationState` owns transient presentation details such as the table of contents and crop state. The Reader Shell owns the window and routes user input to the feature that owns the behavior. Portable state and services live in `LeafReaderCore`; PDFKit, WebKit, AppKit, SwiftUI, network, and concrete speech adapters remain in `LeafReaderApp`.

`SpeechSynthesisRuntime` is the dispatch seam between Read Aloud and concrete local speech engines. Platform-neutral SQLite stores and runtime download primitives live in Core, while macOS-specific clients and runtime adapters live under the app's `Platform` directory.

## Navigation Rules

- Start in the feature directory named by the user-visible behavior.
- Put portable domain state and policy in `LeafReaderCore`; keep framework-bound rendering and adapters in `LeafReaderApp`.
- Use `ReaderWindowController` extensions as feature entry points, not as forwarding coordinators.
- Keep lifecycle state in its owning model (`DocumentSession`, review session, or note/editor state) rather than in the window shell.
- Place reusable UI in `SharedUI`; place service adapters in `Platform`.
- Keep tests alongside the feature under `Tests/LeafReaderTests/` and run them with `scripts/run_tests.sh`.

## High-Leverage Files

- `Sources/LeafReaderApp/ReaderShell/ReaderWindowController.swift`
- `Sources/LeafReaderApp/DocumentReading/DocumentSession.swift`
- `Sources/LeafReaderCore/DocumentReading/DocumentLoading.swift`
- `Sources/LeafReaderApp/AIConversation/AIChatPanel.swift`
- `Sources/LeafReaderCore/AIConversation/PDFEmbeddingStore.swift`
- `Sources/LeafReaderApp/ReadAloud/SpeechSynthesisRuntime.swift`
- `Sources/LeafReaderApp/Platform/SpeechRuntime/SpeechRuntimeResourceManager.swift`
- `Sources/LeafReaderApp/VocabularyReview/WordRecordSQLiteStore.swift`
