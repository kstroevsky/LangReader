import Foundation

/// Stable accessibility identifiers for the migrated SwiftUI screens.
///
/// These are a contract, not decoration. `scripts/check_ui_smoke.sh` drives the
/// real app and asserts these identifiers are present, which is the only
/// automated coverage the SwiftUI screens have — none of it survives renaming
/// an identifier, so they live here rather than as string literals scattered
/// through the views.
///
/// Identifiers are deliberately not localised: the smoke test must find the
/// same control whatever interface language the app is running in.
enum ReadingNotesAccessibility {
    static let searchField = "notes.search"
    static let summaryLabel = "notes.summary"
    static let exportButton = "notes.export"
    static let closeButton = "notes.close"
    static let row = "notes.row"
    static let favoriteButton = "notes.row.favorite"
    static let deleteButton = "notes.row.delete"
}

enum GeneralSettingsAccessibility {
    static let languagePicker = "settings.general.language"
    static let themePicker = "settings.general.theme"
    static let brightnessSlider = "settings.general.brightness"
    static let speakWordToggle = "settings.general.speakWord"
    static let saveConversationToggle = "settings.general.saveConversation"
}

enum ModelSettingsAccessibility {
    static let modelPicker = "settings.model.picker"
    static let endpointField = "settings.model.endpoint"
    static let modelNameField = "settings.model.name"
    static let apiKeyField = "settings.model.apiKey"
    static let testButton = "settings.model.testChat"
}

enum EmbeddingSettingsAccessibility {
    static let providerPicker = "settings.embedding.picker"
    static let endpointField = "settings.embedding.endpoint"
    static let modelNameField = "settings.embedding.model"
    static let apiKeyField = "settings.embedding.apiKey"
    static let testButton = "settings.embedding.testConnection"
    static let autoIndexToggle = "settings.embedding.autoIndex"
}

enum CacheSettingsAccessibility {
    static let buildIndex = "settings.cache.buildIndex"
    static let pauseIndex = "settings.cache.pauseIndex"
    static let cancelIndex = "settings.cache.cancelIndex"
    static let clearBookIndex = "settings.cache.clearBookIndex"
    static let clearBookWords = "settings.cache.clearBookWords"
    static let clearAllCache = "settings.cache.clearAllCache"
}

enum SpeechSettingsAccessibility {
    static let runtimePicker = "settings.speech.runtime"
    static let voicePicker = "settings.speech.voice"
    static let speedPicker = "settings.speech.speed"
    static let diagnosticsButton = "settings.speech.diagnostics"
    // Per-runtime action identifiers are these prefixes plus the runtime id.
    static let downloadPrefix = "settings.speech.download."
    static let pausePrefix = "settings.speech.pause."
    static let cancelPrefix = "settings.speech.cancel."
    static let deletePrefix = "settings.speech.delete."
}

enum ShelfAccessibility {
    static let addButton = "shelf.add"
    static let clearButton = "shelf.clear"
    static let closeButton = "shelf.close"
    static let card = "shelf.card"
}

enum VocabularyLibraryAccessibility {
    static let row = "vocabulary.row"
    static let copyButton = "vocabulary.detail.copy"
    static let removeButton = "vocabulary.detail.remove"
    static let sourceButton = "vocabulary.detail.source"
}
