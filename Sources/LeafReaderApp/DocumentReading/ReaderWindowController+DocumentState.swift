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

    /// The reader's semantic selection. Feature code reads this focused model
    /// directly; native PDF/Web selection remains owned by the active adapter.
    var selectionState: ReaderSelectionState {
        get { documentSession.selection }
        set { documentSession.selection = newValue }
    }

    var currentWebPlainText: String {
        get { documentSession.web.plainText }
        set { documentSession.web.plainText = newValue }
    }

    var webPlainTextGeneration: Int {
        get { documentSession.web.plainTextGeneration }
    }

    var pendingWebProgressRestore: ReaderWebPresentation.PendingProgressRestore? {
        get { documentSession.web.pendingProgressRestore }
        set { documentSession.web.pendingProgressRestore = newValue }
    }

    /// The logical document title. Read this — not `titleLabel.stringValue` —
    /// wherever the title is wanted as *data* (AI context, embedding, read-aloud),
    /// because the label is transiently overwritten with read-aloud progress.
    /// `setDocumentTitle(_:)` is the only writer; it keeps the label in step.
    var documentTitle: String {
        documentSession.presentation.documentTitle
    }

    func setDocumentTitle(_ title: String) {
        documentSession.presentation.setDocumentTitle(title)
        titleLabel.stringValue = title
    }

    /// The editable zoom field reflects this model value. PDFKit remains the
    /// rendering adapter; it reports its scale through
    /// `syncPDFZoomPercentFromNative()` after a native change.
    var pdfZoomPercent: Int {
        documentSession.presentation.pdfZoomPercent
    }

    func setPDFZoomPercent(_ percent: Int) {
        documentSession.presentation.setPDFZoomPercent(percent)
    }

    func syncPDFZoomPercentFromNative() {
        guard currentDocumentKind == .pdf, let percent = pdfReaderAdapter.nativeZoomPercent else { return }
        setPDFZoomPercent(percent)
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
        var selection = selectionState
        selection.pdfSelectedText = ""
        selectionState = selection
    }
}
