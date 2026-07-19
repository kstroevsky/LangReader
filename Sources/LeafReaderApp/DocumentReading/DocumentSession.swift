import Cocoa

/// The document-scoped state that survives while one document is open in the Reader Shell.
///
/// A load ticket and the plain-text generation make asynchronous EPUB/DOCX work harmless
/// after the reader opens another document or unloads the current one.
struct DocumentSession {
    var currentFileURL: URL?
    var lastSavedSessionBookmarkURL: URL?
    var currentFileMD5: String?
    var sessionStore = ReaderSessionStore(fileMD5: nil)
    var currentDocumentKind: ReaderDocumentKind = .pdf
    private(set) var documentLoadGeneration = 0
    var currentPDFSelectedText = ""
    var currentWebPlainText = ""
    private(set) var webPlainTextGeneration = 0
    var currentWebSelectedText = ""
    var currentWebSelectionContext = ""
    var currentWebSelectionOccurrenceIndex: Int?
    var currentWebSelectionRect: NSRect?
    var pendingWebProgressRestore: (generation: Int, progress: Double, zoomPercent: Int?)?
    var webZoomPercent = 100
    var webScrollProgress: Double = 0
    var lastWebProgressSave = Date.distantPast
    var lastPageIndex: Int?
    var lastPersonalVocabularyPDFPageIndex: Int?
    var lastPersonalVocabularyWebProgressBucket: Int?
    var isRestoringSession = false

    mutating func beginLoading() -> Int {
        documentLoadGeneration += 1
        return documentLoadGeneration
    }

    func acceptsLoad(generation: Int) -> Bool {
        documentLoadGeneration == generation
    }

    mutating func adopt(url: URL, kind: ReaderDocumentKind, documentID: String?) {
        resetDocumentBoundState(invalidateLoad: false)
        currentFileURL = url
        currentFileMD5 = documentID
        sessionStore = ReaderSessionStore(fileMD5: documentID)
        currentDocumentKind = kind
    }

    mutating func unload() {
        resetDocumentBoundState(invalidateLoad: true)
    }

    private mutating func resetDocumentBoundState(invalidateLoad: Bool) {
        let nextLoadGeneration = documentLoadGeneration + (invalidateLoad ? 1 : 0)
        let nextWebPlainTextGeneration = webPlainTextGeneration + 1
        let bookmarkURL = lastSavedSessionBookmarkURL
        let restoringSession = isRestoringSession

        self = Self()
        documentLoadGeneration = nextLoadGeneration
        webPlainTextGeneration = nextWebPlainTextGeneration
        lastSavedSessionBookmarkURL = bookmarkURL
        isRestoringSession = restoringSession
    }
}
