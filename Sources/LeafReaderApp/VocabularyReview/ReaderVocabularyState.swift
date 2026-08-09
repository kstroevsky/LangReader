import Foundation
import NaturalLanguage
import PDFKit
import LeafReaderCore

struct ReaderVocabularyState {
    /// Language the current document's vocabulary is lemmatized and grouped by.
    /// Detected on load; defaults to English until then.
    var documentLanguage: NLLanguage = .english
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
}
