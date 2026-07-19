# Feature Map

Use this page when the task starts from a product behavior. Every path is rooted at `Sources/LeafReaderApp/`.

## App And Reader Shell

- `App/`: lifecycle, menu commands, diagnostics, versioning, and Sparkle updates.
- `ReaderShell/`: reader window, chrome, keyboard and selection state, shelf, recent documents, and session restoration.
- `SharedUI/`: reusable reader chrome, theme, export, selection, search, and Markdown views.

## Document Reading

- `DocumentReading/DocumentSession.swift`: active Document lifecycle, load generation, restoration, and teardown.
- `DocumentReading/DocumentPresentationState.swift`: table of contents, crop, and other transient presentation state.
- `DocumentReading/DocumentImportDecision.swift`: import policy for files and dropped content.
- `DocumentReading/DocumentLoading*.swift`: EPUB/DOCX/archive decoding and HTML generation.
- `DocumentReading/PDFReaderView.swift` and `PDFPagingPolicy.swift`: PDFKit interaction and edge paging.
- `DocumentReading/ReaderWindowController+Document*.swift`: document commands and lifecycle entry points.
- `Resources/reader-web*.js`: WebKit reader selection, search, and highlight behavior.

## AI Conversation And Analysis

- `AIConversation/AIChatPanel*.swift`: chat UI, bubbles, request lifecycle, actions, and export.
- `AIConversation/AIPromptStore.swift` with `Resources/AIPrompts.json`: built-in prompt templates.
- `AIConversation/ReaderWindowController+AI*.swift`: Reader Shell integration, retrieval, sources, and state.
- `AIConversation/ReaderWindowController+Embedding*.swift`: indexing lifecycle, progress, cache controls, and retrieval.
- `AIConversation/PDFDocumentAgentIndex.swift` and `PDFEmbeddingStore.swift`: document chunking and embedding cache.
- `Platform/Networking/AIClient.swift` and `EmbeddingClient.swift`: provider HTTP and streaming boundaries.

## Vocabulary Review

- `VocabularyReview/ReaderWindowController+Vocabulary*.swift`: capture, highlighting, navigation, persistence, and review UI.
- `VocabularyReview/VocabularySRS.swift`, `VocabularyReviewSession.swift`, and `VocabularyReviewQueueBuilder.swift`: review scoring and queue policy.
- `VocabularyReview/WordRecordSQLiteStore.swift`, `PDFWordRecordStore.swift`, and `WebWordRecordStore.swift`: vocabulary persistence.
- `VocabularyReview/VocabularyExporter.swift`: Markdown and Anki CSV export.

## Reading Notes

- `ReadingNotes/ReaderWindowController+ReadingNotes.swift`: Reader Shell integration.
- `ReadingNotes/ReadingNoteStore.swift`: note persistence and schema migration.
- `ReadingNotes/ReadingNotesPanelController.swift`: note list, search, and callbacks.
- `ReadingNotes/ReadingNotePanelController*.swift`: editor, Markdown, images, AI actions, and menu commands.

## Read Aloud

- `ReadAloud/SpeechPlaybackCoordinator*.swift`: segmentation, synthesis queue, playback, and progress notifications.
- `ReadAloud/SpeechSynthesisRuntime.swift`: selected engine policy and synthesis dispatch.
- `ReadAloud/ReaderWindowController+ReadAloud*.swift`: PDF/Web entry points, controls, and visual progress.
- `Platform/SpeechRuntime/`: local engine installation, availability, downloads, catalog, and concrete TTS backends.
- `Settings/AISettingsPanelController+Speech.swift`: speech settings and runtime management UI.

## Platform And Release

- `Platform/Persistence/`: local encrypted data and shared SQLite migrations.
- `Platform/Networking/`: provider and embedding clients plus connectivity/error formatting.
- `docs/appcast.xml`: Sparkle feed; `docs/index.html`: download page.
- `scripts/release_pkg.sh` and `scripts/publish_release.sh`: package and publish workflow.
- `scripts/generate_code_wiki.sh`: regenerate the generated wiki indexes.
