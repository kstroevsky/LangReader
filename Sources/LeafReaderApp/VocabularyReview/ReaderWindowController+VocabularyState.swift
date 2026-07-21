import Foundation
import NaturalLanguage

extension ReaderWindowController {
    /// Language the current document's vocabulary is grouped by. All lemma
    /// resolution and occurrence scanning for saved words must use this one
    /// value so their grouping keys stay consistent.
    var vocabularyDocumentLanguage: NLLanguage {
        get { vocabularyState.documentLanguage }
        set { vocabularyState.documentLanguage = newValue }
    }

    var storedWordRecords: [StoredPDFWordRecord] {
        get { vocabularyState.storedWordRecords }
        set { vocabularyState.storedWordRecords = newValue }
    }

    var pendingPDFWordRecords: [String: PendingPDFWordRecord] {
        get { vocabularyState.pendingPDFWordRecords }
        set { vocabularyState.pendingPDFWordRecords = newValue }
    }

    var pdfWordRecordStore: PDFWordRecordStore? {
        get { vocabularyState.pdfWordRecordStore }
        set { vocabularyState.pdfWordRecordStore = newValue }
    }

    var storedWebWordRecords: [StoredWebWordRecord] {
        get { vocabularyState.storedWebWordRecords }
        set { vocabularyState.storedWebWordRecords = newValue }
    }

    var pendingWebWordRecords: [String: PendingWebWordRecord] {
        get { vocabularyState.pendingWebWordRecords }
        set { vocabularyState.pendingWebWordRecords = newValue }
    }

    var webWordRecordStore: WebWordRecordStore? {
        get { vocabularyState.webWordRecordStore }
        set { vocabularyState.webWordRecordStore = newValue }
    }

    var currentVocabularyExportRecords: [VocabularyExportRecord] {
        get { vocabularyState.currentExportRecords }
        set { vocabularyState.currentExportRecords = newValue }
    }
}
