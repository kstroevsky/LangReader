# Feature Map

Use this page when the task starts from a product behavior. Paths explicitly identify either `Sources/LeafReaderCore/` or `Sources/LeafReaderApp/`.

## App And Reader Shell

- `App/`: lifecycle, menu commands, diagnostics, versioning, and Sparkle updates.
- `ReaderShell/`: reader window, chrome, keyboard and selection state, shelf, recent documents, and session restoration.
- `SharedUI/`: reusable reader chrome, theme, export, selection, search, and Markdown views.

## Document Reading

- App `DocumentReading/DocumentSession.swift`: active document lifecycle, load generation, restoration, and teardown.
- App `DocumentReading/DocumentPresentationState.swift`: table of contents, crop, and other transient presentation state.
- Core `DocumentReading/DocumentImportDecision.swift`: import policy for files and dropped content.
- Core `DocumentReading/DocumentLoading*.swift`: EPUB/DOCX/archive decoding and HTML generation.
- App `DocumentReading/PDFReaderView.swift` and `ReaderWindowController+Navigation.swift`: PDFKit interaction and page navigation.
- App `DocumentReading/ReaderWindowController+Document*.swift`: document commands and lifecycle entry points.
- App `Resources/reader-web*.js`: WebKit reader selection, search, and highlight behavior.

## AI Conversation And Analysis

- App `AIConversation/AIChatPanel*.swift`: chat UI, bubbles, request lifecycle, actions, and export.
- Core `AIConversation/AIPromptStore.swift` with app `Resources/AIPrompts.json`: built-in prompt templates.
- App `AIConversation/ReaderWindowController+AI*.swift`: Reader Shell integration, retrieval, sources, and state.
- App `AIConversation/ReaderWindowController+Embedding*.swift`: indexing lifecycle, progress, cache controls, and retrieval.
- App `AIConversation/PDFDocumentAgentIndex.swift` and Core `AIConversation/PDFEmbeddingStore.swift`: document chunking and embedding cache.
- App `Platform/Networking/AIClient.swift` and `EmbeddingClient.swift`: provider HTTP and streaming boundaries.

## Vocabulary Review

- App `VocabularyReview/ReaderWindowController+Vocabulary*.swift`: capture, highlighting, navigation, persistence, and review UI.
- Core `VocabularyReview/VocabularySRS.swift`, `VocabularyReviewSession.swift`, and `VocabularyReviewQueueBuilder.swift`: review scoring and queue policy.
- App `VocabularyReview/WordRecordSQLiteStore.swift`, `PDFWordRecordStore.swift`, and `WebWordRecordStore.swift`: vocabulary persistence adapters.
- Core `VocabularyReview/VocabularyExporter.swift`: Markdown and Anki CSV export.

## Reading Notes

- App `ReadingNotes/ReaderWindowController+ReadingNotes.swift`: Reader Shell integration.
- Core `ReadingNotes/ReadingNoteStore.swift`: note persistence and schema migration.
- App `ReadingNotes/ReadingNotesPanelController.swift`: note list, search, and callbacks.
- App `ReadingNotes/ReadingNotePanelController*.swift`: editor, Markdown, images, AI actions, and menu commands.

## Read Aloud

- App `ReadAloud/SpeechPlaybackCoordinator*.swift`: synthesis queue, playback, and progress notifications.
- App `ReadAloud/SpeechSynthesisRuntime.swift`: selected engine policy and synthesis dispatch.
- Core `ReadAloud/`: text normalization, segmentation, matching, and shortcut policies.
- App `ReadAloud/ReaderWindowController+ReadAloud*.swift`: PDF/Web entry points, controls, and visual progress.
- Core and App `Platform/SpeechRuntime/`: download infrastructure plus macOS installation, availability, catalog, and concrete TTS backends.
- App `Settings/AISettingsPanelController+Speech.swift`: speech settings integration; `SpeechSettingsView.swift` renders the page.

## Platform And Release

- `Platform/Persistence/`: local encrypted data and shared SQLite migrations.
- `Platform/Networking/`: provider and embedding clients plus connectivity/error formatting.
- `docs/appcast.xml`: Sparkle feed; `docs/index.html`: download page.
- `scripts/release_pkg.sh` and `scripts/publish_release.sh`: package and publish workflow.
- `scripts/generate_code_wiki.sh`: regenerate the generated wiki indexes.
