import AVFoundation
import Cocoa
import CryptoKit
import PDFKit
import UniformTypeIdentifiers
import WebKit
import LeafReaderCore

final class ReaderWindowController: NSWindowController, NSWindowDelegate, PDFViewDelegate, NSTextFieldDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    struct PendingPDFWordRecord {
        let id: String
        let vocabularyID: String
        let word: String
        let pageIndex: Int
        let bounds: StoredPDFWordRect
        let textAnchor: TextQuoteAnchor?
        let context: String
        var dictionaryTags: String?
        var dictionaryFrequency: Int?
        let createdAt: Date
    }

    struct PendingWebWordRecord {
        let id: String
        let vocabularyID: String
        let word: String
        let lemma: String
        let surfaceForm: String
        let context: String
        let occurrenceIndex: Int?
        let scrollProgress: Double
        var dictionaryTags: String?
        var dictionaryFrequency: Int?
        let createdAt: Date
    }

    enum PendingReadAloudPDFContinuation {
        case currentScreen(startAtPageTop: Bool)
        case afterCurrentScreen
        case afterBatch(lastQueuedPage: PDFPage)
        case waitForPage(expectedPageIndex: Int?, previousPageIndex: Int?, startAtPageTop: Bool)
    }

    enum ReadAloudContinuationTrigger: Equatable {
        case automatic
        case userAdvance
    }

    static let preferredAIWidthDefaultsKey = "preferredAIWidth"
    static let pdfTwoPageModeDefaultsKey = "pdfTwoPageMode"
    static let pdfMarginCropDefaultsKey = "pdfMarginCrop"
    nonisolated static let fileMD5CacheDefaultsKey = "fileMD5Cache"
    static let embeddingControlStateDefaultsKey = "embeddingControlState"
    static let minimumReadablePDFScale: CGFloat = 1.0
    static let capsuleButtonIdentifier = NSUserInterfaceItemIdentifier("leafReaderCapsuleButton")
    static let readAloudLanguageProbePageLimit = 3

    var pdfView: ReaderPDFView!
    var webView: ReaderWebView!
    lazy var pdfReaderAdapter = PDFKitReaderAdapter(view: pdfView)
    lazy var webReaderAdapter = WebKitReaderAdapter(view: webView)
    /// The active native rendering adapter. It is selected only when a Document
    /// Session begins loading and consumed through the reader backend seam.
    var activeReaderBackend: (any ReaderContentBackend)?
    let contentArea = NSView()
    let pdfContainer = ClippingView()
    let pdfDimOverlay = PassthroughOverlayView()
    let loadingOverlay = NSView()
    let loadingIndicator = NSProgressIndicator()
    let loadingLabel = NSTextField(labelWithString: "")
    let aiPanel = AIChatPanel()
    lazy var vocabularySpeechSynthesizer = AVSpeechSynthesizer()
    lazy var vocabularySpeechCoordinator = VocabularySpeechCoordinator(
        synthesizer: vocabularySpeechSynthesizer,
        owner: self
    )
    let aiHandleButton = SideHandleButton(title: "", target: nil, action: nil)
    let resizeHandle = ResizeHandleView()
    let titleLabel = WindowDragTextField(labelWithString: AppIdentity.displayName)
    let coverImageView = WindowDragImageView()
    let pageLabel = ClickEditableTextField(string: AppText.noPDF)
    let zoomField = ClickEditableTextField(string: "100%")
    let searchOverlay = SearchOverlayView()
    let selectionActionToolbar = SelectionActionToolbar()
    var selectionActionToolbarWindow: NSWindow?
    /// Last chrome state applied; the source of truth for what is on screen.
    var chromeState: ReaderChromeState = .empty
    var readerPresentation = ReaderShellPresentationState()
    let topBarModel = ReaderTopBarModel()
    let bottomBarModel = ReaderBottomBarModel()
    var searchButton: NSButton!
    var searchUnderlineButton: SearchUnderlineButton!
    weak var toolbarView: NSView?
    weak var bottomBarView: NSView?
    weak var zoomGroupView: NSView?
    var documentSession = DocumentSession()
    var activeWebDocumentLoadCancellationToken: DocumentLoadCancellationToken?
    var documentPresentationState = DocumentPresentationState()
    var activeVisibleDocumentLoadStartedAt: TimeInterval?
    var activeVisibleDocumentLoadKind: ReaderDocumentKind?
    var activeVisibleDocumentLoadIsSessionRestore = false
    var pendingPDFCoverThumbnailRequest: (url: URL, documentID: String?)?
    var pendingPDFTOCBuildRequest: (url: URL, displayBox: PDFDisplayBox)?
    /// Hits for the current PDF query. The web path keeps its hits in the page,
    /// so only the PDF side stores them here.
    var searchResults: [PDFSelection] = []
    /// Which hit is selected and how the query changed — shared by both paths.
    var searchCursor = ReaderSearchCursor()
    var activePDFSearchDocument: PDFDocument?
    var activePDFSearchQuery = ""
    var activePDFSearchStartedAt: TimeInterval?
    var activePDFSearchFirstResultStartedAt: TimeInterval?
    var webSearchGeneration = 0
    var performanceAutomationKinds = Set<ReaderDocumentKind>()
    var performanceAutomationOriginalPDFRecordIDs = Set<String>()
    var didRegisterPDFSearchObservers = false
    var pdfVocabularyAnnotationRestoreGeneration = 0
    var pdfNoteAnnotationRestoreGeneration = 0
    var documentTextState = ReaderDocumentTextState()
    var embeddingState = ReaderEmbeddingState()
    var aiState = ReaderAIState()
    let sessionSaveTask = DebouncedTask(delay: ReaderSessionPolicy.lastPositionSaveDelay)
    var vocabularyState = ReaderVocabularyState()
    var notesState = ReaderNotesState()
    let pdfWordRecordsSaveTask = DebouncedTask(delay: 0.8)
    let webWordRecordsSaveTask = DebouncedTask(delay: 0.8)
    var readAloudState = ReaderReadAloudState()
    var didRegisterSelectionObserver = false
    var isEditingZoomField = false
    var isEditingPageField = false
    var aiSettingsPanelController: AISettingsPanelController?
    var recentDocumentsPanelController: RecentDocumentsPanelController?
    var readingNotesPanelController: ReadingNotesPanelController?
    var vocabularyPanelController: VocabularyPanelController!
    var vocabularyLibraryWindowController: VocabularyLibraryWindowController!
    var vocabularyPreparationCoordinator: VocabularyPreparationCoordinator!
    var vocabularyPreparationPanelController: VocabularyPreparationPanelController!
    nonisolated let vocabularyLibraryBuildCache = VocabularyLibraryBuildCache()
    lazy var selectionToolbarCoordinator = SelectionToolbarCoordinator(owner: self)
    let vocabularyReviewSession = VocabularyReviewSession()
    var aiHandleLeadingConstraint: NSLayoutConstraint!
    var aiPanelWidthConstraint: NSLayoutConstraint!
    var localEventMonitor: Any?

    override init(window: NSWindow?) {
        super.init(window: window)
        readerPresentation.preferredAIWidth = Self.loadPreferredAIWidth()
        vocabularyPanelController = VocabularyPanelController(owner: self)
        vocabularyLibraryWindowController = VocabularyLibraryWindowController(owner: self)
        vocabularyPreparationCoordinator = VocabularyPreparationCoordinator(
            documentSource: self,
            library: self
        )
        vocabularyPreparationPanelController = VocabularyPreparationPanelController(
            coordinator: vocabularyPreparationCoordinator
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    convenience init() {
        let window = ReaderWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = AppIdentity.displayName
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = ReaderTheme.selected.chromeBackgroundColor
        window.setFrameAutosaveName("LeafVocabularyMainWindow")
        window.center()
        let dropContentView = ReaderDropContentView(frame: window.contentView?.bounds ?? .zero)
        dropContentView.autoresizingMask = [.width, .height]
        window.contentView = dropContentView

        self.init(window: window)
        dropContentView.readerWindowController = self
        window.readerWindowController = self
        window.delegate = self
        LaunchPerformanceTracker.shared.mark("windowShell")
        buildUI()
        LaunchPerformanceTracker.shared.mark("buildUI")
        installSpeechProgressObserver()
        LaunchPerformanceTracker.shared.mark("speechObserver")
    }

    deinit {
        // NSWindowController and every resource below are main-thread objects.
        // Swift 6 treats deinit as nonisolated, so state the AppKit lifetime
        // invariant explicitly while tearing them down.
        MainActor.assumeIsolated {
            if let localEventMonitor {
                NSEvent.removeMonitor(localEventMonitor)
            }
            sessionSaveTask.cancel()
            activeWebDocumentLoadCancellationToken?.cancel()
            aiConversationSaveTask.cancel()
            preferredAIWidthSaveTask.cancel()
            windowResizeLayoutTask.cancel()
            aiPanelResizeLayoutTask.cancel()
            pendingAISourceClickWorkItem?.cancel()
            cancelDocumentAgentPrompt()
            pdfWordRecordsSaveTask.cancel()
            webWordRecordsSaveTask.cancel()
            vocabularyPanelController.close()
            vocabularyLibraryWindowController.close()
            vocabularyPreparationCoordinator.cancel()
            vocabularyPreparationPanelController.close()
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "selectionChanged")
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "scrollChanged")
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "webWordClicked")
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "webNoteClicked")
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "webAISourceClicked")
            NotificationCenter.default.removeObserver(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        if !handlePageKey(event) {
            super.keyDown(with: event)
        }
    }
}
