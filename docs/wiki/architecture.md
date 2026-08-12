# Architecture

Leaf Reader is a native macOS reader built with Swift, AppKit, SwiftUI, PDFKit, WebKit, and Sparkle. The shipping application is split into a platform-neutral, domain-focused `LeafReaderCore` module and a macOS `LeafReaderApp` module.

Framework-free does not automatically mean Core. Core owns product semantics, parsing, persistence formats, algorithms, and policies. Presentation models, formatting, accessibility identifiers, design tokens, toolbar descriptions, and window-coordinate geometry remain in the app even when they import only Foundation. A shared UI target should be introduced only when another platform such as iOS creates a real consumer.

## Source Tree

```text
Sources/LeafReaderCore/
  AIConversation/      prompts, response formatting, conversation data, embedding storage
  DocumentReading/     document decoding, identity, semantic selection, and domain policies
  Platform/            portable persistence and local-runtime infrastructure
  ReadAloud/           speech text, matching, and keyboard policies
  ReaderShell/         portable reader-session domain state
  ReadingNotes/        note models, persistence, Markdown, assets, and export
  SharedUI/            legacy framework-free policies; not a destination for new presentation types
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

`DocumentSession` owns the active document identity, load generation, restoration data, and teardown. `DocumentPresentationState` owns transient presentation details such as the table of contents and crop state. The Reader Shell owns the window and routes user input to the feature that owns the behavior. Domain state and services that are also platform-neutral live in `LeafReaderCore`; presentation state plus PDFKit, WebKit, AppKit, SwiftUI, network, and concrete speech adapters remain in `LeafReaderApp`.

`SpeechSynthesisRuntime` is the dispatch seam between Read Aloud and concrete local speech engines. Platform-neutral SQLite stores and runtime download primitives live in Core, while macOS-specific clients and runtime adapters live under the app's `Platform` directory.

## Navigation Rules

- Start in the feature directory named by the user-visible behavior.
- Put platform-neutral domain state and policy in `LeafReaderCore`. Keep presentation types in `LeafReaderApp` even when they are framework-free.
- Use `ReaderWindowController` as the composition root and feature entry point: coordinate and delegate, but do not add domain rules to it.
- Keep lifecycle state in its owning model (`DocumentSession`, review session, or note/editor state) rather than in the window shell.
- Place reusable UI in `SharedUI`; place service adapters in `Platform`.
- Route PDFKit/WebKit feature intent through reader adapters or narrow platform services. Treat `reader_native_access_allowlist.txt` as debt that may shrink but must not be expanded merely to pass a check.
- Put Core tests under `Tests/LeafReaderCoreTests/`, app tests under `Tests/LeafReaderAppTests/`, and legacy regression-harness tests under `Tests/LeafReaderTests/`.

`scripts/check_core_portable.sh` enforces framework independence. Its app-file list proves technical portability only; it is not a queue of types that should move into Core.

## High-Leverage Files

- `Sources/LeafReaderApp/ReaderShell/ReaderWindowController.swift`
- `Sources/LeafReaderApp/DocumentReading/DocumentSession.swift`
- `Sources/LeafReaderCore/DocumentReading/DocumentLoading.swift`
- `Sources/LeafReaderApp/AIConversation/AIChatPanel.swift`
- `Sources/LeafReaderCore/AIConversation/PDFEmbeddingStore.swift`
- `Sources/LeafReaderApp/ReadAloud/SpeechSynthesisRuntime.swift`
- `Sources/LeafReaderApp/Platform/SpeechRuntime/SpeechRuntimeResourceManager.swift`
- `Sources/LeafReaderApp/VocabularyReview/WordRecordSQLiteStore.swift`
