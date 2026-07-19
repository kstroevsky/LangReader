import Cocoa

extension ReaderWindowController {
    var currentFileURL: URL? {
        get { documentSession.currentFileURL }
        set { documentSession.currentFileURL = newValue }
    }

    var lastSavedSessionBookmarkURL: URL? {
        get { documentSession.lastSavedSessionBookmarkURL }
        set { documentSession.lastSavedSessionBookmarkURL = newValue }
    }

    var currentFileMD5: String? {
        get { documentSession.currentFileMD5 }
        set { documentSession.currentFileMD5 = newValue }
    }

    var sessionStore: ReaderSessionStore {
        get { documentSession.sessionStore }
        set { documentSession.sessionStore = newValue }
    }

    var currentDocumentKind: ReaderDocumentKind {
        get { documentSession.currentDocumentKind }
        set { documentSession.currentDocumentKind = newValue }
    }

    var documentLoadGeneration: Int {
        get { documentSession.documentLoadGeneration }
    }

    var currentPDFSelectedText: String {
        get { documentSession.currentPDFSelectedText }
        set { documentSession.currentPDFSelectedText = newValue }
    }

    var currentWebPlainText: String {
        get { documentSession.currentWebPlainText }
        set { documentSession.currentWebPlainText = newValue }
    }

    var webPlainTextGeneration: Int {
        get { documentSession.webPlainTextGeneration }
    }

    var currentWebSelectedText: String {
        get { documentSession.currentWebSelectedText }
        set { documentSession.currentWebSelectedText = newValue }
    }

    var currentWebSelectionContext: String {
        get { documentSession.currentWebSelectionContext }
        set { documentSession.currentWebSelectionContext = newValue }
    }

    var currentWebSelectionOccurrenceIndex: Int? {
        get { documentSession.currentWebSelectionOccurrenceIndex }
        set { documentSession.currentWebSelectionOccurrenceIndex = newValue }
    }

    var currentWebSelectionRect: NSRect? {
        get { documentSession.currentWebSelectionRect }
        set { documentSession.currentWebSelectionRect = newValue }
    }

    var pendingWebProgressRestore: (generation: Int, progress: Double, zoomPercent: Int?)? {
        get { documentSession.pendingWebProgressRestore }
        set { documentSession.pendingWebProgressRestore = newValue }
    }

    var currentDocumentDiagnostics: [String] {
        get { documentPresentationState.currentDocumentDiagnostics }
        set { documentPresentationState.currentDocumentDiagnostics = newValue }
    }

    var currentTOCItems: [ReaderTOCItem] {
        get { documentPresentationState.currentTOCItems }
        set { documentPresentationState.currentTOCItems = newValue }
    }

    var pdfTOCDestinations: [String: ReaderTOCHelper.PDFTOCDestination] {
        get { documentPresentationState.pdfTOCDestinations }
        set { documentPresentationState.pdfTOCDestinations = newValue }
    }

    var pdfTOCGeneration: Int {
        get { documentPresentationState.pdfTOCGeneration }
        set { documentPresentationState.pdfTOCGeneration = newValue }
    }

    var webZoomPercent: Int {
        get { documentSession.webZoomPercent }
        set { documentSession.webZoomPercent = newValue }
    }

    var webScrollProgress: Double {
        get { documentSession.webScrollProgress }
        set { documentSession.webScrollProgress = newValue }
    }

    var originalPDFCropBoxes: [Int: CGRect] {
        get { documentPresentationState.originalPDFCropBoxes }
        set { documentPresentationState.originalPDFCropBoxes = newValue }
    }

    var lastWebProgressSave: Date {
        get { documentSession.lastWebProgressSave }
        set { documentSession.lastWebProgressSave = newValue }
    }

    var lastPageIndex: Int? {
        get { documentSession.lastPageIndex }
        set { documentSession.lastPageIndex = newValue }
    }

    var lastPersonalVocabularyPDFPageIndex: Int? {
        get { documentSession.lastPersonalVocabularyPDFPageIndex }
        set { documentSession.lastPersonalVocabularyPDFPageIndex = newValue }
    }

    var lastPersonalVocabularyWebProgressBucket: Int? {
        get { documentSession.lastPersonalVocabularyWebProgressBucket }
        set { documentSession.lastPersonalVocabularyWebProgressBucket = newValue }
    }

    var isRestoringSession: Bool {
        get { documentSession.isRestoringSession }
        set { documentSession.isRestoringSession = newValue }
    }

    func clearPDFSelectionState() {
        currentPDFSelectedText = ""
    }
}
