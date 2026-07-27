import Cocoa
import LeafReaderCore

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

    /// The reader's current selection. The individual accessors below forward
    /// into it so the ~70 call sites across the extensions did not have to
    /// change when it moved out of `DocumentSession`.
    var selectionState: ReaderSelectionState {
        get { documentSession.selection }
        set { documentSession.selection = newValue }
    }

    var currentPDFSelectedText: String {
        get { documentSession.selection.pdfSelectedText }
        set { documentSession.selection.pdfSelectedText = newValue }
    }

    var currentWebPlainText: String {
        get { documentSession.web.plainText }
        set { documentSession.web.plainText = newValue }
    }

    var webPlainTextGeneration: Int {
        get { documentSession.web.plainTextGeneration }
    }

    var currentWebSelectedText: String {
        get { documentSession.selection.webSelectedText }
        set { documentSession.selection.webSelectedText = newValue }
    }

    var currentWebSelectionContext: String {
        get { documentSession.selection.webSelectionContext }
        set { documentSession.selection.webSelectionContext = newValue }
    }

    var currentWebSelectionOccurrenceIndex: Int? {
        get { documentSession.selection.webSelectionOccurrenceIndex }
        set { documentSession.selection.webSelectionOccurrenceIndex = newValue }
    }

    var currentWebSelectionRect: NSRect? {
        get { documentSession.selectionPresentation.anchorRect }
        set { documentSession.selectionPresentation.anchorRect = newValue }
    }

    var pendingWebProgressRestore: ReaderWebPresentation.PendingProgressRestore? {
        get { documentSession.web.pendingProgressRestore }
        set { documentSession.web.pendingProgressRestore = newValue }
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
        get { documentSession.web.zoomPercent }
        set { documentSession.web.zoomPercent = newValue }
    }

    var webScrollProgress: Double {
        get { documentSession.web.scrollProgress }
        set { documentSession.web.scrollProgress = newValue }
    }

    var originalPDFCropBoxes: [Int: CGRect] {
        get { documentPresentationState.originalPDFCropBoxes }
        set { documentPresentationState.originalPDFCropBoxes = newValue }
    }

    var lastWebProgressSave: Date {
        get { documentSession.web.lastProgressSave }
        set { documentSession.web.lastProgressSave = newValue }
    }

    var lastPageIndex: Int? {
        get { documentSession.position.lastPageIndex }
        set { documentSession.position.lastPageIndex = newValue }
    }

    var lastPersonalVocabularyPDFPageIndex: Int? {
        get { documentSession.position.lastPersonalVocabularyPDFPageIndex }
        set { documentSession.position.lastPersonalVocabularyPDFPageIndex = newValue }
    }

    var lastPersonalVocabularyWebProgressBucket: Int? {
        get { documentSession.position.lastPersonalVocabularyWebProgressBucket }
        set { documentSession.position.lastPersonalVocabularyWebProgressBucket = newValue }
    }

    var isRestoringSession: Bool {
        get { documentSession.isRestoringSession }
        set { documentSession.isRestoringSession = newValue }
    }

    func clearPDFSelectionState() {
        currentPDFSelectedText = ""
    }
}
