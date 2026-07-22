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
