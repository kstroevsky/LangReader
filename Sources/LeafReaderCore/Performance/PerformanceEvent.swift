import Foundation

/// A surface whose responsiveness we hold a baseline for.
///
/// Adding a case is the whole cost of tracking a new surface: the recorder,
/// the report, and the baseline file are all driven off `allCases`, so a new
/// event shows up in every one of them without a second edit.
///
/// The raw value is the stable key written to the committed baseline JSON —
/// renaming a case silently orphans its history, so treat these as an on-disk
/// contract, not just an identifier.
package enum PerformanceEvent: String, CaseIterable, Sendable {
    case launch
    case mainWindow
    case pdfOpen
    case webOpen
    case firstPageDisplay
    case shelfOpen
    case notesOpen
    case vocabularyLibraryOpen
    case aiPanelExpand
    case selectionToolbar
    case pdfTextSnapshot
    case vocabularyIndexBuild
    case vocabularySaveAcknowledgement
    case vocabularyOccurrenceQuery
    case vocabularyOccurrencePersistence
    case visibleHighlightMaterialization
    case pdfSearch
    case aiFirstToken
    case aiStreaming
    case themeSwitch

    /// A short human label for the report table. Kept apart from `rawValue` so
    /// the on-disk key can stay stable while the label is free to read better.
    package var label: String {
        switch self {
        case .launch: return "App launch"
        case .mainWindow: return "Main window"
        case .pdfOpen: return "PDF open"
        case .webOpen: return "EPUB/DOCX open"
        case .firstPageDisplay: return "First page display"
        case .shelfOpen: return "Shelf open"
        case .notesOpen: return "Notes open"
        case .vocabularyLibraryOpen: return "Vocabulary Library open"
        case .aiPanelExpand: return "AI panel expansion"
        case .selectionToolbar: return "Selection toolbar"
        case .pdfTextSnapshot: return "PDF text snapshot"
        case .vocabularyIndexBuild: return "Vocabulary index build"
        case .vocabularySaveAcknowledgement: return "Vocabulary save acknowledgement"
        case .vocabularyOccurrenceQuery: return "Vocabulary occurrence query"
        case .vocabularyOccurrencePersistence: return "Vocabulary occurrence persistence"
        case .visibleHighlightMaterialization: return "Visible highlight materialization"
        case .pdfSearch: return "PDF search"
        case .aiFirstToken: return "AI first token"
        case .aiStreaming: return "AI streaming (per chunk)"
        case .themeSwitch: return "Theme switch"
        }
    }
}
