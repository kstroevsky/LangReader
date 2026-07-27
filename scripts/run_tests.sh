#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_SOURCE_ROOT="Sources/LeafReaderApp"
TEST_SOURCE_ROOT="Tests/LeafReaderTests"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/private/tmp/leafreader-clang-cache}"

# The logic tests link `LeafReaderCore` as a real module rather than compiling
# its sources in. That keeps the tests honest about the boundary: a test can
# only reach what the core actually exposes, and a core type that quietly starts
# needing AppKit fails when the module is built, not here.
CORE_BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leafreader-core-tests.XXXXXX")"
trap 'rm -rf "$CORE_BUILD_DIR"' EXIT
./scripts/build_core_module.sh "$CORE_BUILD_DIR" >/dev/null
CORE_MODULE_FLAGS=(
  -package-name LeafReader
  -I "$CORE_BUILD_DIR"
  -L "$CORE_BUILD_DIR"
  -lLeafReaderCore
)

run_swift_test() {
  local output="$1"
  shift
  swiftc "${CORE_MODULE_FLAGS[@]}" "$@" -o "$output"
  "$output"
}

LOGIC_APP_SOURCES=()

always_include_logic_app_source() {
  local base="$1"
  case "$base" in
    ReadingNoteEditorViews.swift|SelectionToolbarConfiguration.swift|ReaderChromeState.swift|ReaderToolbarItem.swift)
      return 0
      ;;
  esac
  return 1
}

excluded_logic_app_source() {
  local base="$1"
  case "$base" in
    main.swift|\
    AppDelegate*|\
    AIChatPanel*|\
    AISettingsPanel*|\
    GeneralSettingsModel.swift|\
    GeneralSettingsView.swift|\
    ReadingNotesListModel.swift|\
    AITextActionRunner.swift|\
    AIClient.swift|\
    DebouncedTask.swift|\
    DiagnosticsPanel*|\
    DiagnosticsReport.swift|\
    DocumentLoading*|\
    DocumentQuestionPromptRequest.swift|\
    DocumentPresentationState.swift|\
    EmbeddingClient.swift|\
    LeafAlertStyle.swift|\
    LLMAnswerProvider.swift|\
    ModalOverlayManager.swift|\
    PDFDocumentAgentIndex.swift|\
    PDFEmbeddingStore.swift|\
    GermanFlexionStore.swift|\
    GermanCachedFormLabeling.swift|\
    VocabularyCachedFormLabeling.swift|\
    PDFWordRecordStore.swift|\
    Reader*State.swift|\
    ReaderDropContentView.swift|\
    ReaderFileDrop.swift|\
    ReaderTheme*|\
    ReaderDesignTokens.swift|\
    ShelfColorTokens.swift|\
    ReadingNoteColorTokens.swift|\
    VocabularyListColorTokens.swift|\
    ReaderWebThemeCSS.swift|\
    ReaderTOCHelper.swift|\
    ReaderWindowController*|\
    ReaderWindowSupportViews.swift|\
    ReadingNotePanelController*|\
    ReadingNoteEditorRenderer.swift|\
    ReadingNoteTheme.swift|\
    RecentDocuments*|\
    SearchOverlayView.swift|\
    SelectionActionToolbar.swift|\
    SelectionToolbarCoordinator.swift|\
    SettingsTabsView.swift|\
    SpeechPlayback*|\
    TemplateSymbolImage.swift|\
    ThemedSettings*|\
    TTSPreviewCache.swift|\
    VocabularyContextProvider.swift|\
    VocabularyDictionaryMetadataService.swift|\
    VocabularyFrequencyBackfillService.swift|\
    VocabularyRecordProvider.swift|\
    VocabularyLibraryBuildCache.swift|\
    VocabularyReviewCardFooterBuilder.swift|\
    VocabularyReviewScoringService.swift|\
    VocabularySpeechCoordinator.swift|\
    WebReadAloudBatchParser.swift|\
    WebWordRecordStore.swift|\
    WordRecordSQLite*.swift|\
    *Button.swift|\
    *Controls.swift|\
    *Overlay*.swift|\
    *Toolbar*.swift|\
    *View.swift|\
    *Views.swift)
      return 0
      ;;
  esac
  return 1
}

contains_ui_dependency() {
  local source="$1"
  grep -Eq '\b(NSView|NSWindow|NSButton|NSImageView|NSPanel|NSScrollView|WKWebView|PDFView|PDFAnnotation|AVAudio|NSSavePanel|NSOpenPanel|NSMenu|NSAlert|NSCollectionView|NSTextView|NSVisualEffectView|NSToolbar)\b' "$source"
}

collect_logic_app_sources() {
  local source
  local base
  LOGIC_APP_SOURCES=()

  while IFS= read -r source; do
    base="${source##*/}"
    if always_include_logic_app_source "$base"; then
      LOGIC_APP_SOURCES+=("$source")
      continue
    fi
    if excluded_logic_app_source "$base" || contains_ui_dependency "$source"; then
      continue
    fi
    LOGIC_APP_SOURCES+=("$source")
  done < <(find "$APP_SOURCE_ROOT" -name "*.swift" -type f | LC_ALL=C sort)
}

SQLITE_WORD_TEST_SOURCES=(
  "$TEST_SOURCE_ROOT/VocabularyReview/SQLiteWordRecordStoreTests.swift"
  "$APP_SOURCE_ROOT/VocabularyReview/VocabularySRS.swift"
  "$APP_SOURCE_ROOT/VocabularyReview/PDFWordRecordStore.swift"
  "$APP_SOURCE_ROOT/VocabularyReview/WebWordRecordStore.swift"
  "$APP_SOURCE_ROOT/Platform/Persistence/SQLiteSchemaMigrator.swift"
  "$APP_SOURCE_ROOT/VocabularyReview/WordRecordSQLiteRowMapper.swift"
  "$APP_SOURCE_ROOT/VocabularyReview/WordRecordSQLiteStore.swift"
  "$APP_SOURCE_ROOT/VocabularyReview/GermanFlexionStore.swift"
  "$APP_SOURCE_ROOT/VocabularyReview/GermanLabelCacheGeneration.swift"
)

PERSONAL_VOCABULARY_TEST_SOURCES=(
  "$TEST_SOURCE_ROOT/VocabularyReview/PersonalVocabularyProfileStoreTests.swift"
  "$APP_SOURCE_ROOT/VocabularyReview/PersonalVocabularyProfile.swift"
  "$APP_SOURCE_ROOT/VocabularyReview/PersonalVocabularyProfileStore.swift"
)

REGRESSION_TEST_SOURCES=(
  "$APP_SOURCE_ROOT/App/LaunchPerformanceTracker.swift"
  "$APP_SOURCE_ROOT/AIConversation/AIRequestState.swift"
  "$APP_SOURCE_ROOT/SharedUI/MarkdownRenderer.swift"
  "$APP_SOURCE_ROOT/SharedUI/MarkdownBlockParser.swift"
  "$APP_SOURCE_ROOT/SharedUI/MarkdownInlineParser.swift"
  "$TEST_SOURCE_ROOT/Support/RegressionTests.swift"
)

LOGIC_TEST_SOURCES=(
  "$TEST_SOURCE_ROOT/AIConversation/AIConversationContextStoreTests.swift"
  "$TEST_SOURCE_ROOT/AIConversation/AITranscriptModelTests.swift"
  "$TEST_SOURCE_ROOT/DocumentReading/ReaderSearchCursorTests.swift"
  "$TEST_SOURCE_ROOT/Performance/PerformanceRecorderTests.swift"
  "$TEST_SOURCE_ROOT/DocumentReading/ReaderPresentationStateTests.swift"
  "$TEST_SOURCE_ROOT/DocumentReading/ReaderFieldInputTests.swift"
  "$TEST_SOURCE_ROOT/DocumentReading/ReaderChromeStateTests.swift"
  "$TEST_SOURCE_ROOT/DocumentReading/ReaderToolbarItemTests.swift"
  "$TEST_SOURCE_ROOT/DocumentReading/ReaderBottomBarItemTests.swift"
  "$TEST_SOURCE_ROOT/DocumentReading/EPUBLogicTests.swift"
  "$TEST_SOURCE_ROOT/DocumentReading/DocumentImportDecisionLogicTests.swift"
  "$TEST_SOURCE_ROOT/DocumentReading/DocumentSessionLogicTests.swift"
  "$TEST_SOURCE_ROOT/ReadingNotes/ReadingNoteLogicTests.swift"
  "$TEST_SOURCE_ROOT/ReadingNotes/ReadingNoteEditorModelTests.swift"
  "$TEST_SOURCE_ROOT/DocumentReading/ReaderShelfLogicTests.swift"
  "$TEST_SOURCE_ROOT/App/ShelfCardPresenterTests.swift"
  "$TEST_SOURCE_ROOT/VocabularyReview/VocabularyLibraryFilterTests.swift"
  "$TEST_SOURCE_ROOT/VocabularyReview/VocabularyOccurrenceGroupingTests.swift"
  "$TEST_SOURCE_ROOT/AIConversation/AISettingsTestSupport.swift"
  "$TEST_SOURCE_ROOT/AIConversation/AISettingsLogicTests.swift"
  "$TEST_SOURCE_ROOT/ReadAloud/SpeechRuntimeLogicTests.swift"
  "$TEST_SOURCE_ROOT/ReadAloud/SpeechSynthesisRuntimeTests.swift"
  "$TEST_SOURCE_ROOT/ReadAloud/SpeechRuntimeBackendTests.swift"
  "$TEST_SOURCE_ROOT/ReadAloud/SpeechRuntimeDownloadTests.swift"
  "$TEST_SOURCE_ROOT/ReadAloud/SpeechRuntimeManifestTests.swift"
  "$TEST_SOURCE_ROOT/ReadAloud/SpeechRuntimeAvailabilityTests.swift"
  "$TEST_SOURCE_ROOT/VocabularyReview/ECDICTLogicTests.swift"
  "$TEST_SOURCE_ROOT/VocabularyReview/GermanDictionaryLogicTests.swift"
  "$TEST_SOURCE_ROOT/VocabularyReview/GermanLemmaFixtureTests.swift"
  "$TEST_SOURCE_ROOT/VocabularyReview/GermanFormLabelerTests.swift"
  "$TEST_SOURCE_ROOT/VocabularyReview/GermanFlexionParserTests.swift"
  "$TEST_SOURCE_ROOT/VocabularyReview/VocabularyLogicTests.swift"
  "$TEST_SOURCE_ROOT/Support/LogicTests.swift"
)

node --check "$APP_SOURCE_ROOT/Resources/reader-web-text.js"
node --check "$APP_SOURCE_ROOT/Resources/reader-web-search.js"
node --check "$APP_SOURCE_ROOT/Resources/reader-web-marks.js"
node --check "$APP_SOURCE_ROOT/Resources/reader-web.js"
node "$TEST_SOURCE_ROOT/DocumentReading/ReaderWebScriptTests.js"

collect_logic_app_sources

run_swift_test /tmp/leafreader-sqlite-word-tests \
  "${SQLITE_WORD_TEST_SOURCES[@]}" \
  -framework Cocoa \
  -lsqlite3

run_swift_test /tmp/leafreader-personal-vocabulary-tests \
  "${PERSONAL_VOCABULARY_TEST_SOURCES[@]}" \
  -lsqlite3

run_swift_test /tmp/leafreader-pdf-embedding-store-tests \
  "$TEST_SOURCE_ROOT/DocumentReading/PDFEmbeddingStoreTests.swift" \
  "$APP_SOURCE_ROOT/AIConversation/PDFDocumentAgentIndex.swift" \
  "$APP_SOURCE_ROOT/AIConversation/ReaderAIContextBuilder+PDF.swift" \
  -framework PDFKit \
  -framework Cocoa \
  -lsqlite3

run_swift_test /tmp/leafreader-regression-tests \
  "${REGRESSION_TEST_SOURCES[@]}" \
  -framework Cocoa

run_swift_test /tmp/leafreader-update-failure-classifier-tests \
  "$APP_SOURCE_ROOT/App/UpdateFailureClassifier.swift" \
  "$TEST_SOURCE_ROOT/App/UpdateFailureClassifierTests.swift"

run_swift_test /tmp/leafreader-theme-palette-tests \
  "$APP_SOURCE_ROOT/SharedUI/ReaderTheme.swift" \
  "$APP_SOURCE_ROOT/SharedUI/ReaderTheme+Palette.swift" \
  "$APP_SOURCE_ROOT/SharedUI/ReaderDesignTokens.swift" \
  "$APP_SOURCE_ROOT/SharedUI/ReaderWebThemeCSS.swift" \
  "$APP_SOURCE_ROOT/ReaderShell/ShelfColorTokens.swift" \
  "$APP_SOURCE_ROOT/ReadingNotes/ReadingNoteTheme.swift" \
  "$APP_SOURCE_ROOT/ReadingNotes/ReadingNoteColorTokens.swift" \
  "$APP_SOURCE_ROOT/VocabularyReview/VocabularyListColorTokens.swift" \
  "$TEST_SOURCE_ROOT/App/ReaderThemePaletteTests.swift" \
  "$TEST_SOURCE_ROOT/App/ReaderDesignTokenTests.swift" \
  -framework Cocoa

run_swift_test /tmp/leafreader-vocabulary-record-provider-tests \
  "$TEST_SOURCE_ROOT/VocabularyReview/VocabularyRecordProviderTests.swift" \
  "$APP_SOURCE_ROOT/VocabularyReview/VocabularySRS.swift" \
  "$APP_SOURCE_ROOT/VocabularyReview/VocabularyExportRecord.swift" \
  "$APP_SOURCE_ROOT/VocabularyReview/VocabularyRecordProvider.swift" \
  "$APP_SOURCE_ROOT/VocabularyReview/GermanFormLabeler.swift" \
  -framework Cocoa \
  -framework NaturalLanguage

run_swift_test /tmp/leafreader-vocabulary-library-record-provider-tests \
  "$TEST_SOURCE_ROOT/VocabularyReview/VocabularyLibraryRecordProviderTests.swift" \
  "$APP_SOURCE_ROOT/VocabularyReview/VocabularySRS.swift" \
  "$APP_SOURCE_ROOT/VocabularyReview/VocabularyExportRecord.swift" \
  "$APP_SOURCE_ROOT/VocabularyReview/VocabularyLibraryModels.swift" \
  "$APP_SOURCE_ROOT/VocabularyReview/GermanFormLabeler.swift" \
  -framework Cocoa \
  -framework NaturalLanguage

run_swift_test /tmp/leafreader-logic-tests \
  "${LOGIC_APP_SOURCES[@]}" \
  "${LOGIC_TEST_SOURCES[@]}" \
  -framework PDFKit \
  -framework Cocoa \
  -framework Network \
  -framework NaturalLanguage \
  -lsqlite3

if [[ -n "${LEAFREADER_TEST_PDF_WITH_ANSWERS:-}" && -n "${LEAFREADER_TEST_PDF_WITHOUT_ANSWERS:-}" ]]; then
  swiftc \
    "$TEST_SOURCE_ROOT/DocumentReading/PDFVocabularyDocumentTests.swift" \
    "$APP_SOURCE_ROOT/VocabularyReview/VocabularyOccurrenceMatcher.swift" \
    -framework PDFKit \
    -o /tmp/leafreader-pdf-vocabulary-document-tests
  /tmp/leafreader-pdf-vocabulary-document-tests \
    "$LEAFREADER_TEST_PDF_WITH_ANSWERS" \
    "$LEAFREADER_TEST_PDF_WITHOUT_ANSWERS"
fi

if [[ -n "${LEAFREADER_TEST_APP_BUNDLE:-}" ]]; then
  "$TEST_SOURCE_ROOT/ReadAloud/PiperRuntimeBundleTests.sh" "$LEAFREADER_TEST_APP_BUNDLE"
fi

if [[ "${LEAFVOCABULARY_TEST_GERMAN_DICTIONARY:-0}" == "1" ]]; then
  run_swift_test /tmp/leafvocabulary-german-dictionary-live-tests \
    "$TEST_SOURCE_ROOT/VocabularyReview/GermanDictionaryLiveLookupTests.swift" \
    "$APP_SOURCE_ROOT/VocabularyReview/GermanWiktionaryDictionary.swift" \
      -lsqlite3
fi
