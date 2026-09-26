import Foundation
import PDFKit
import LeafReaderCore

struct ReaderVocabularyState {
    /// Authoritative semantic language state for the current document.
    /// It is intentionally unresolved until detection, persisted metadata, or
    /// a manual user selection provides evidence.
    private(set) var documentLanguageResolution: VocabularyLanguageResolution = .notYetAnalyzed
    private(set) var languageRevision: UInt64 = 0
    var storedWordRecords: [StoredPDFWordRecord] = []
    var pendingPDFWordRecords: [String: ReaderWindowController.PendingPDFWordRecord] = [:]
    var pdfWordRecordStore: PDFWordRecordStore?
    var storedWebWordRecords: [StoredWebWordRecord] = []
    var pendingWebWordRecords: [String: ReaderWindowController.PendingWebWordRecord] = [:]
    var webWordRecordStore: WebWordRecordStore?
    var currentExportRecords: [VocabularyExportRecord] = []
    var occurrenceSearchID: UUID?
    var occurrenceSearchCancellationToken: PDFDocumentTextCancellationToken?
    var expandedOccurrenceKeys: Set<String> = []
    var pendingLibraryOccurrence: VocabularyLibraryOccurrence?
    var renderedPDFWordAnnotations: [(page: PDFPage, annotation: PDFAnnotation)] = []
    var resolvedPDFWordBounds: [String: CGRect] = [:]

    @discardableResult
    mutating func updateLanguageResolution(
        _ resolution: VocabularyLanguageResolution,
        replacingUserSelection: Bool = false
    ) -> Bool {
        if !replacingUserSelection,
           documentLanguageResolution.resolvedLanguage?.provenance == .userSelected,
           resolution.resolvedLanguage?.provenance != .userSelected {
            return false
        }
        guard documentLanguageResolution != resolution else { return false }
        documentLanguageResolution = resolution
        languageRevision &+= 1
        return true
    }

    mutating func resetLanguageResolution() {
        _ = updateLanguageResolution(.notYetAnalyzed, replacingUserSelection: true)
    }
}
