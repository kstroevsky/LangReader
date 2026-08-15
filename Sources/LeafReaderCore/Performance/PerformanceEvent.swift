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
    case webDocumentPreparation
    case epubPreparation
    case docxPreparation
    case docxFingerprint
    case docxCacheLookup
    case docxCacheHitLoad
    case docxArchiveExtraction
    case docxRelationshipParse
    case docxXMLRender
    case docxCacheCommit
    case webOpen
    case webContentReady
    case epubContentReady
    case docxContentReady
    case firstPageDisplay
    case pdfCoverThumbnail
    case documentVisibleReady
    case pdfVisibleReady
    case epubVisibleReady
    case docxVisibleReady
    case restoredDocumentVisibleReady
    case shelfOpen
    case notesOpen
    case vocabularyLibraryOpen
    case aiPanelExpand
    case selectionToolbar
    case pdfTextSnapshot
    case pdfTextSnapshotCacheLoad
    case vocabularyIndexBuild
    case vocabularyPreparationInventoryBuild
    case vocabularyAssessmentAdvance
    case vocabularyPreparationResults
    case vocabularyPreparationImport
    case vocabularySaveAcknowledgement
    case vocabularyOccurrenceQuery
    case vocabularyOccurrencePersistence
    case vocabularyRecordLoad
    case vocabularyRecordRepair
    case vocabularyLanguageDetection
    case vocabularyDatabaseWrite
    case visibleHighlightMaterialization
    case webHighlightRestore
    case webSourceNavigation
    case pdfSearch
    case searchAcknowledgement
    case searchFirstVisibleResult
    case searchCancellationResponse
    case searchResultNavigation
    case pdfZoomHighlightUpdate
    case webFontHighlightUpdate
    case mainThreadUninterruptedWork
    case idleScrollFrame
    case backgroundIndexScrollFrame
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
        case .webDocumentPreparation: return "EPUB/DOCX preparation"
        case .epubPreparation: return "EPUB preparation"
        case .docxPreparation: return "DOCX preparation"
        case .docxFingerprint: return "DOCX fingerprint"
        case .docxCacheLookup: return "DOCX cache lookup"
        case .docxCacheHitLoad: return "DOCX cache hit load"
        case .docxArchiveExtraction: return "DOCX archive extraction"
        case .docxRelationshipParse: return "DOCX relationship parse"
        case .docxXMLRender: return "DOCX XML render"
        case .docxCacheCommit: return "DOCX cache commit"
        case .webOpen: return "EPUB/DOCX open"
        case .webContentReady: return "EPUB/DOCX content ready"
        case .epubContentReady: return "EPUB content ready"
        case .docxContentReady: return "DOCX content ready"
        case .firstPageDisplay: return "First page display"
        case .pdfCoverThumbnail: return "PDF cover thumbnail"
        case .documentVisibleReady: return "Document visibly ready"
        case .pdfVisibleReady: return "PDF visibly ready"
        case .epubVisibleReady: return "EPUB visibly ready"
        case .docxVisibleReady: return "DOCX visibly ready"
        case .restoredDocumentVisibleReady: return "Restored document visibly ready"
        case .shelfOpen: return "Shelf open"
        case .notesOpen: return "Notes open"
        case .vocabularyLibraryOpen: return "Vocabulary Library open"
        case .aiPanelExpand: return "AI panel expansion"
        case .selectionToolbar: return "Selection toolbar"
        case .pdfTextSnapshot: return "PDF text snapshot"
        case .pdfTextSnapshotCacheLoad: return "PDF text snapshot cache load"
        case .vocabularyIndexBuild: return "Vocabulary index build"
        case .vocabularyPreparationInventoryBuild: return "Preparation inventory build"
        case .vocabularyAssessmentAdvance: return "Assessment answer to next card"
        case .vocabularyPreparationResults: return "Preparation results presentation"
        case .vocabularyPreparationImport: return "Preparation atomic import"
        case .vocabularySaveAcknowledgement: return "Vocabulary save acknowledgement"
        case .vocabularyOccurrenceQuery: return "Vocabulary occurrence query"
        case .vocabularyOccurrencePersistence: return "Vocabulary occurrence persistence"
        case .vocabularyRecordLoad: return "Vocabulary record load"
        case .vocabularyRecordRepair: return "Vocabulary record repair"
        case .vocabularyLanguageDetection: return "Vocabulary language detection"
        case .vocabularyDatabaseWrite: return "Vocabulary database write"
        case .visibleHighlightMaterialization: return "Visible highlight materialization"
        case .webHighlightRestore: return "Web highlight restoration"
        case .webSourceNavigation: return "Web source navigation"
        case .pdfSearch: return "PDF search"
        case .searchAcknowledgement: return "Search acknowledgement"
        case .searchFirstVisibleResult: return "Search first visible result"
        case .searchCancellationResponse: return "Search cancellation response"
        case .searchResultNavigation: return "Search result navigation"
        case .pdfZoomHighlightUpdate: return "PDF zoom highlight update"
        case .webFontHighlightUpdate: return "Web font highlight update"
        case .mainThreadUninterruptedWork: return "Main-thread uninterrupted work"
        case .idleScrollFrame: return "Idle scroll frame delay"
        case .backgroundIndexScrollFrame: return "Background-index scroll frame delay"
        case .aiFirstToken: return "AI first token"
        case .aiStreaming: return "AI streaming (per chunk)"
        case .themeSwitch: return "Theme switch"
        }
    }
}
