# Development Tasks

Use this page when a task starts with a product behavior. Paths marked App are rooted at `Sources/LeafReaderApp/`; paths marked Core are rooted at `Sources/LeafReaderCore/`. Feature tests are under `Tests/LeafReaderTests/`.

## Change PDF Page Turning

Start with App `DocumentReading/PDFReaderView.swift`, `DocumentReading/ReaderWindowController+Navigation.swift`, and the paged backend in `DocumentReading/ReaderWindowController+Backend.swift`.

Run `./scripts/check.sh --no-build`. Preserve PDFKit viewport restoration and verify that each toolbar or keyboard action advances exactly one page.

## Change AI Translation Or Explanations

Start with App `AIConversation/AIChatPanel+Actions.swift` and `AIConversation/AIChatPanel+Requests.swift`, plus Core `AIConversation/AIResponseTextFormatter.swift` and `AIConversation/AIPromptStore.swift`. Prompt templates are in App `Resources/AIPrompts.json`; HTTP behavior belongs in App `Platform/Networking/AIClient.swift`.

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

Start with App `AIConversation/ReaderWindowController+Embedding*.swift`, App `AIConversation/PDFDocumentAgentIndex.swift`, Core `AIConversation/PDFEmbeddingStore.swift` and `AIConversation/EmbeddingActionPolicy.swift`, and App `Platform/Networking/EmbeddingClient.swift`. Settings integration is in App `Settings/AISettingsPanelController+Model.swift`, `EmbeddingSettingsModel.swift`, and `EmbeddingSettingsView.swift`.

Run `./scripts/check.sh --no-build`. Preserve valid cached chunks and keep status accurate after pause, cancellation, failure, and theme changes.

## Change Vocabulary Review

Start with App `VocabularyReview/ReaderWindowController+VocabularyReviewUI.swift`, `ReaderWindowController+VocabularyReviewSRS.swift`, `ReaderWindowController+VocabularyReviewQueue.swift`, and `WordRecordSQLiteStore.swift`, plus Core `VocabularyReview/VocabularySRS.swift`.

Run `./scripts/check.sh --no-build`. Do not delete user vocabulary data unintentionally; keep PDF and Web records aligned.

## Change Read Aloud Or TTS Models

Start with App `ReadAloud/SpeechPlaybackCoordinator.swift`, `ReadAloud/SpeechSynthesisRuntime.swift`, `ReadAloud/ReaderWindowController+ReadAloud*.swift`, and App/Core `Platform/SpeechRuntime/`. Speech settings are in App `Settings/AISettingsPanelController+Speech.swift`, `SpeechSettingsModel.swift`, and `SpeechSettingsView.swift`.

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
