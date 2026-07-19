# Development Tasks

Use this page when a task starts with a product behavior. Paths below are rooted at `Sources/LeafReaderApp/`; feature-local tests are under `Tests/LeafReaderTests/`.

## Change PDF Page Turning

Start with `DocumentReading/PDFReaderView.swift`, `DocumentReading/PDFPagingPolicy.swift`, and `DocumentReading/ReaderWindowController+Navigation.swift`.

Run `./scripts/check.sh --no-build`. Preserve PDFKit scrolling and check duplicate page turns after a single edge gesture.

## Change AI Translation Or Explanations

Start with `AIConversation/AIChatPanel+Actions.swift`, `AIConversation/AIChatPanel+Requests.swift`, `AIConversation/AIResponseTextFormatter.swift`, and `AIConversation/AIPromptStore.swift`. Prompt templates are in `Resources/AIPrompts.json`; HTTP behavior belongs in `Platform/Networking/AIClient.swift`.

Run `./scripts/check.sh --no-build`. Check streaming cleanup, selected-text titles, and paragraph preservation.

## Change UI Controls Or Theme Styling

Start in the feature that owns the surface, then inspect `SharedUI/ReaderTheme.swift` and `SharedUI/ReaderTheme+Palette.swift`. Common feature entry points are `ReaderShell/ReaderWindowController+Theme.swift`, `AIConversation/AIChatPanel+BubbleStyling.swift`, `ReadingNotes/ReadingNotePanelController+Theme.swift`, and `Settings/AISettingsPanelController+Theme.swift`.

Run:

```sh
./scripts/check.sh --no-build
./scripts/check_ui_theme.sh --warnings-as-errors
./scripts/build_app.sh
```

Every visible control must have a current-theme creation path and an existing-view refresh path for original, eye-care, and dark themes.

## Change Whole-Book AI Analysis

Start with `AIConversation/ReaderWindowController+Embedding*.swift`, `AIConversation/PDFDocumentAgentIndex.swift`, `AIConversation/PDFEmbeddingStore.swift`, `AIConversation/EmbeddingActionPolicy.swift`, and `Platform/Networking/EmbeddingClient.swift`. Settings integration is in `Settings/AISettingsPanelController+ModelEmbedding.swift`.

Run `./scripts/check.sh --no-build`. Preserve valid cached chunks and keep status accurate after pause, cancellation, failure, and theme changes.

## Change Vocabulary Review

Start with `VocabularyReview/ReaderWindowController+VocabularyReviewUI.swift`, `VocabularyReview/ReaderWindowController+VocabularyReviewSRS.swift`, `VocabularyReview/ReaderWindowController+VocabularyReviewQueue.swift`, `VocabularyReview/VocabularySRS.swift`, and `VocabularyReview/WordRecordSQLiteStore.swift`.

Run `./scripts/check.sh --no-build`. Do not delete user vocabulary data unintentionally; keep PDF and Web records aligned.

## Change Read Aloud Or TTS Models

Start with `ReadAloud/SpeechPlaybackCoordinator.swift`, `ReadAloud/SpeechSynthesisRuntime.swift`, `ReadAloud/ReaderWindowController+ReadAloud*.swift`, and `Platform/SpeechRuntime/`. Speech settings are in `Settings/AISettingsPanelController+Speech.swift` and `Settings/AISettingsPanelController+BuildSpeech.swift`.

Run:

```sh
./scripts/run_tests.sh
./scripts/build_app.sh --release --universal
./scripts/audit_app_bundle.sh
```

Ensure a downloaded model is runnable before presenting it as selectable, retain at most one local TTS model in memory, and verify PDF and Web temporary highlights.

## Change Bookshelf Or Session Restore

Start with `ReaderShell/RecentDocumentsPanelController*.swift`, `ReaderShell/RecentDocumentsStore.swift`, `ReaderShell/ReaderWindowController+DocumentShelf.swift`, and `ReaderShell/ReaderWindowController+Session.swift`. The active document lifecycle is owned by `DocumentReading/DocumentSession.swift`.

Run `./scripts/check.sh --no-build`. Verify stable document identity, sort/import behavior, and that shelf actions unload only the intended Document Session.

## Publish A New Version

Start with `docs/wiki/release-checklist.md`, `docs/wiki/release-runbook.md`, `scripts/release_pkg.sh`, `scripts/publish_release.sh`, `docs/appcast.xml`, and `docs/index.html`.

Run `./scripts/check.sh`, then `./scripts/update_wiki.sh --push` when remote credentials are available. Confirm version references, signing, notarization, and Sparkle metadata agree.
