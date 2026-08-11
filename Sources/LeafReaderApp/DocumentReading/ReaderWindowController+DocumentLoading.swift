import Cocoa
import PDFKit
import LeafReaderCore

private enum ReaderPDFCoverThumbnailLoader {
    static let queue = DispatchQueue(
        label: "com.linlu.leafreader.pdf-cover-thumbnail",
        qos: .utility
    )
}

extension ReaderWindowController {
    func loadPDF(_ url: URL, generation: Int? = nil) {
        let openSpan = ReaderPerformance.begin(.pdfOpen)
        let firstPageSpan = ReaderPerformance.begin(.firstPageDisplay)
        defer { ReaderPerformance.end(openSpan) }
        guard let document = PDFDocument(url: url) else {
            if let generation {
                showDocumentLoadingFailure(
                    NSError(domain: "LeafReader", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: AppText.localized("无法打开 PDF。", "Unable to open PDF.")
                    ]),
                    generation: generation
                )
            }
            return
        }
        closeReadingNotePanelsForDocumentTransition()
        activateDocumentSession(url: url, kind: .pdf)
        pdfView.isHidden = false
        webView.isHidden = true
        pdfView.document = document
        captureOriginalPDFCropBoxes()
        applyPDFMarginCropIfNeeded()
        pdfWordRecordStore = currentFileMD5.map { PDFWordRecordStore(fileMD5: $0) }
        webWordRecordStore = nil
        schedulePDFTOCBuild(for: url, displayBox: pdfView.displayBox)
        storedWordRecords = loadStoredWordRecords()
        storedWebWordRecords.removeAll()
        loadReadingNotesForCurrentDocument()
        aiPanel.loadLinkedWordBubbles(pdfWordRecordStore?.linkedWordBubbles(from: storedWordRecords) ?? [])
        loadSavedAIConversationIfNeeded()
        setDocumentTitle(ReaderPresentationState.documentTitle(for: url))
        applyDocumentDiagnostics([], fileName: url.lastPathComponent)
        scheduleCoverThumbnail(for: url, documentID: currentFileMD5)
        refreshChromeState(presentation: .pdf)
        updatePDFMarginCropButton()
        applyPDFPageLayout(animated: false)
        // Page geometry is set; the first page is now laid out for display. The
        // PDFView still rasterises tiles asynchronously, so this is the
        // synchronous "ready to show" point, not the last pixel.
        ReaderPerformance.end(firstPageSpan)
        let annotationDocumentID = currentFileMD5
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.currentDocumentKind == .pdf,
                  self.currentFileMD5 == annotationDocumentID else { return }
            self.restoreStoredWordAnnotationsIncrementally(documentID: annotationDocumentID)
            self.restoreReadingNoteAnnotationsIncrementally(documentID: annotationDocumentID)
        }

        if !didRegisterSelectionObserver {
            didRegisterSelectionObserver = true
            NotificationCenter.default.addObserver(self, selector: #selector(selectionChanged), name: .PDFViewSelectionChanged, object: pdfView)
        }

        restoreBookProgressOrGoHome()
        documentSession.position.lastPageIndex = currentPageIndex()
        syncPDFZoomPercentFromNative()
        applyReaderTheme(refreshDocumentDecorations: false)
        updatePageLabel()
        updateZoomLabel()
        RecentDocumentsStore.record(url: url, kind: .pdf)
        saveSession()
        scheduleDocumentEmbeddingWarmup(priorityPageIndex: currentEmbeddingPriorityIndex())
        completePendingVocabularyLibraryNavigationIfNeeded()
        if let generation {
            finishDocumentLoadingAfterAIBubbles(generation: generation)
        }
    }

    func loadWebDocument(_ url: URL, kind: ReaderDocumentKind, generation: Int) {
        let contentReadyStartedAt = ProcessInfo.processInfo.systemUptime
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let document = try WebDocumentLoader.load(url: url)
                let preparationMilliseconds = (ProcessInfo.processInfo.systemUptime - contentReadyStartedAt) * 1000
                DispatchQueue.main.async {
                    guard let self, self.documentSession.acceptsLoad(generation: generation) else { return }
                    ReaderPerformance.record(.webDocumentPreparation, milliseconds: preparationMilliseconds)
                    ReaderPerformance.record(
                        kind == .epub ? .epubPreparation : .docxPreparation,
                        milliseconds: preparationMilliseconds
                    )
                    self.applyLoadedWebDocument(
                        document,
                        url: url,
                        kind: kind,
                        generation: generation,
                        contentReadyStartedAt: contentReadyStartedAt
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    self?.showDocumentLoadingFailure(error, generation: generation)
                }
            }
        }
    }

    func applyLoadedWebDocument(
        _ document: WebReadableDocument,
        url: URL,
        kind: ReaderDocumentKind,
        generation: Int,
        contentReadyStartedAt: TimeInterval
    ) {
        // The on-main cost of presenting an already-parsed document — the part
        // that blocks the UI. Background parsing in `loadWebDocument` is I/O and
        // measured separately if needed.
        let openSpan = ReaderPerformance.begin(.webOpen)
        defer { ReaderPerformance.end(openSpan) }
        closeReadingNotePanelsForDocumentTransition()
        activateDocumentSession(url: url, kind: kind)
        documentPresentationState.webContentReadyStartedAt = contentReadyStartedAt
        documentPresentationState.webContentReadyDocumentKind = kind
        pdfView.isHidden = true
        pdfDimOverlay.isHidden = true
        webView.isHidden = false
        pdfView.document = nil
        pdfWordRecordStore = nil
        webWordRecordStore = currentFileMD5.map { WebWordRecordStore(fileMD5: $0) }
        currentWebPlainText = document.plainText
        let webPlainTextGeneration = webPlainTextGeneration
        currentDocumentDiagnostics = document.diagnostics
        currentTOCItems = document.tocItems
        storedWordRecords.removeAll()
        storedWebWordRecords = loadStoredWebWordRecords()
        updateVocabularyDocumentLanguage()
        loadReadingNotesForCurrentDocument()
        aiPanel.loadLinkedWordBubbles(webWordRecordStore?.linkedWordBubbles(from: storedWebWordRecords) ?? [])
        loadSavedAIConversationIfNeeded()
        aiPanel.setSelectedText("")
        setDocumentTitle(ReaderPresentationState.documentTitle(for: url))
        applyDocumentDiagnostics(document.diagnostics, fileName: url.lastPathComponent)
        if let coverImageURL = document.coverImageURL, let image = NSImage(contentsOf: coverImageURL) {
            coverImageView.image = image
        } else {
            coverImageView.image = NSImage(systemSymbolName: kind == .epub ? "book.closed" : "doc.text", accessibilityDescription: nil)
        }
        refreshChromeState(presentation: .web)
        updateWebProgressLabel(0)
        updateZoomLabel()
        if let htmlFileURL = document.htmlFileURL {
            webView.loadFileURL(htmlFileURL, allowingReadAccessTo: document.baseURL)
        } else {
            webView.loadHTMLString(document.html, baseURL: document.baseURL)
        }
        applyReaderTheme()
        applyWebZoomToPage()
        restoreWebProgressAfterLoad()
        RecentDocumentsStore.record(url: url, kind: kind)
        saveSession()
        scheduleWebPlainTextLoad(document.plainTextLoader, generation: webPlainTextGeneration)
        scheduleDocumentEmbeddingWarmup(priorityPageIndex: currentEmbeddingPriorityIndex())
        finishDocumentLoadingAfterAIBubbles(generation: generation)
    }

    func activateDocumentSession(url: URL, kind: ReaderDocumentKind) {
        documentSession.adopt(url: url, kind: kind, documentID: fileMD5(for: url))
        documentPresentationState.resetForDocumentChange()
        invalidateDocumentTextState()
        aiConversationStore = currentFileMD5.map { AIConversationStore(fileMD5: $0) }
        loadedAIConversation = nil
        invalidateDocumentAgentIndex()
        pendingPDFWordRecords.removeAll()
        pendingWebWordRecords.removeAll()
        vocabularyState.renderedPDFWordAnnotations.removeAll()
        vocabularyState.resolvedPDFWordBounds.removeAll()
        storedReadingNotes.removeAll()
        readingNotePanelControllers.removeAll()
        lastPersonalVocabularyPDFPageIndex = nil
        lastPersonalVocabularyWebProgressBucket = nil
        cancelScheduledEmbeddingWarmup()
        highlightedSelectionKeys.removeAll()
        clearAISourceUnderlineTracking()
        clearSearchState()
    }

    func applyDocumentDiagnostics(_ diagnostics: [String], fileName: String) {
        guard !diagnostics.isEmpty else {
            titleLabel.toolTip = nil
            return
        }
        let summary = diagnostics.prefix(8).joined(separator: "\n")
        titleLabel.toolTip = AppText.localized(
            "部分 EPUB 内容未能读取：\n\(summary)",
            "Some EPUB content could not be read:\n\(summary)"
        )
        NSLog("LeafReader EPUB diagnostics for %@: %@", fileName, diagnostics.joined(separator: " | "))
    }

    func scheduleWebPlainTextLoad(_ loader: (@Sendable () -> String)?, generation: Int) {
        guard let loader else { return }
        let documentID = currentFileMD5
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let plainText = loader()
            DispatchQueue.main.async {
                guard let self,
                      self.webPlainTextGeneration == generation,
                      self.currentFileMD5 == documentID else {
                    return
                }
                self.currentWebPlainText = plainText
                self.invalidateDocumentAgentIndex()
                self.scheduleDocumentEmbeddingWarmup(priorityPageIndex: self.currentEmbeddingPriorityIndex())
            }
        }
    }

    /// Keeps the cover element in the toolbar without rendering PDF page 1 on
    /// the first-page critical path. A separate PDFDocument is used on the
    /// serial utility queue because the on-screen PDFKit document remains owned
    /// by the main thread.
    func scheduleCoverThumbnail(for url: URL, documentID: String?) {
        coverImageView.image = NSImage(
            systemSymbolName: "doc.richtext",
            accessibilityDescription: AppText.localized("文档封面", "Document cover")
        )
        pendingPDFCoverThumbnailRequest = (url, documentID)
    }

    func startPendingPDFCoverThumbnailIfNeeded() {
        guard let request = pendingPDFCoverThumbnailRequest else { return }
        pendingPDFCoverThumbnailRequest = nil
        let startedAt = ProcessInfo.processInfo.systemUptime
        ReaderPDFCoverThumbnailLoader.queue.async { [weak self] in
            let image = PDFDocument(url: request.url)?.page(at: 0)?.thumbnail(
                of: CGSize(width: 56, height: 76),
                for: .cropBox
            )
            let elapsedMilliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
            DispatchQueue.main.async {
                guard let self,
                      self.currentDocumentKind == .pdf,
                      self.currentFileMD5 == request.documentID,
                      self.currentFileURL?.standardizedFileURL == request.url.standardizedFileURL else { return }
                if let image {
                    self.coverImageView.image = image
                }
                ReaderPerformance.record(.pdfCoverThumbnail, milliseconds: elapsedMilliseconds)
            }
        }
    }
}
