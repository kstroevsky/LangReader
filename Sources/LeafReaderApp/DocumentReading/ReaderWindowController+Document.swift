import Cocoa
import LeafReaderCore

extension ReaderWindowController {
    @objc func openPDF() {
        let panel = NSOpenPanel()
        configureOpenPanel(panel)
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.loadSelectedDocument(url)
        }
    }

    func configureOpenPanel(_ panel: NSOpenPanel) {
        DocumentOpenPanelConfiguration.apply(to: panel)
    }

    func loadDocument(_ url: URL) {
        guard let kind = ReaderDocumentKind.kind(for: url) else { return }
        activeWebDocumentLoadCancellationToken?.cancel()
        activeWebDocumentLoadCancellationToken = nil
        activeVisibleDocumentLoadStartedAt = ProcessInfo.processInfo.systemUptime
        activeVisibleDocumentLoadKind = kind
        activeVisibleDocumentLoadIsSessionRestore = isRestoringSession
        stopReadAloudImmediately()
        SpeechPlaybackCoordinator.shared.shutdownRuntime(.kokoro)
        activateReaderBackend(for: kind)
        let generation = documentSession.beginLoading()
        mutateReaderPresentation { $0.resetForDocumentChange() }
        clearSearchState()
        showDocumentLoading(for: url)
        sessionSaveTask.cancel()
        flushCurrentBookWordRecordSaves()
        saveCurrentAIConversationBeforeDocumentChange()
        resetEmbeddingStateForDocumentChange()
        switch kind {
        case .pdf:
            DispatchQueue.main.async { [weak self] in
                guard let self, self.documentSession.acceptsLoad(generation: generation) else { return }
                self.loadPDF(url, generation: generation)
            }
        case .epub, .docx:
            loadWebDocument(url, kind: kind, generation: generation)
        }
    }

    func showDocumentLoading(for url: URL) {
        loadingLabel.stringValue = AppText.localized("正在打开 \(url.lastPathComponent)...", "Opening \(url.lastPathComponent)...")
        mutateReaderPresentation { $0.beginDocumentLoading() }
    }

    func hideDocumentLoading(generation: Int) {
        guard documentSession.acceptsLoad(generation: generation) else { return }
        mutateReaderPresentation { $0.finishDocumentLoading() }
        if currentDocumentKind == .pdf {
            recordVisibleDocumentReadyIfNeeded()
        }
    }

    func recordVisibleDocumentReadyIfNeeded(
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        guard let startedAt = activeVisibleDocumentLoadStartedAt,
              let kind = activeVisibleDocumentLoadKind,
              currentDocumentKind == kind else { return }
        activeVisibleDocumentLoadStartedAt = nil
        activeVisibleDocumentLoadKind = nil
        let isSessionRestore = activeVisibleDocumentLoadIsSessionRestore
        activeVisibleDocumentLoadIsSessionRestore = false

        let elapsedMilliseconds = max(0, (now - startedAt) * 1_000)
        ReaderPerformance.record(.documentVisibleReady, milliseconds: elapsedMilliseconds)
        switch kind {
        case .pdf:
            ReaderPerformance.record(.pdfVisibleReady, milliseconds: elapsedMilliseconds)
        case .epub:
            ReaderPerformance.record(.epubVisibleReady, milliseconds: elapsedMilliseconds)
        case .docx:
            ReaderPerformance.record(.docxVisibleReady, milliseconds: elapsedMilliseconds)
        }
        if isSessionRestore {
            ReaderPerformance.record(
                .restoredDocumentVisibleReady,
                milliseconds: Double(LaunchPerformanceTracker.shared.elapsedMilliseconds(now: now))
            )
        }
        if kind == .pdf {
            startPendingPDFTOCBuildIfNeeded()
            startPendingPDFCoverThumbnailIfNeeded()
        }
        schedulePerformanceAutomationIfNeeded(for: kind)
    }

    func showDocumentLoadingFailure(_ error: Error, generation: Int) {
        guard documentSession.acceptsLoad(generation: generation) else { return }
        activeVisibleDocumentLoadStartedAt = nil
        activeVisibleDocumentLoadKind = nil
        activeVisibleDocumentLoadIsSessionRestore = false
        pendingPDFCoverThumbnailRequest = nil
        pendingPDFTOCBuildRequest = nil
        hideDocumentLoading(generation: generation)
        let alert = NSAlert(error: error)
        alert.applyLeafStyle()
        alert.runModal()
    }

    func finishDocumentLoadingAfterAIBubbles(generation: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.documentSession.acceptsLoad(generation: generation) else { return }
            self.aiPanel.flushTranscriptLayout()
            self.aiPanel.layoutSubtreeIfNeeded()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.documentSession.acceptsLoad(generation: generation) else { return }
                self.aiPanel.flushTranscriptLayout()
                self.aiPanel.layoutSubtreeIfNeeded()
                self.hideDocumentLoading(generation: generation)
                self.offerVocabularyPreparationIfNeeded(generation: generation)
            }
        }
    }

    func handleDroppedDocumentURLs(_ urls: [URL]) {
        switch DocumentImportDecision.make(urls: urls) {
        case .ignore:
            return
        case let .open(url):
            openDroppedDocument(url)
        case let .showShelf(urls):
            importDocumentsToShelf(urls)
        }
    }

    func openDroppedDocument(_ url: URL) {
        aiSettingsPanelController?.closeWithoutSaving()
        aiSettingsPanelController = nil
        if vocabularyPanelController.panel != nil {
            closeVocabularyPanel()
        }
        if let recentDocumentsPanelController {
            recentDocumentsPanelController.closeThenOpen(path: url.path)
            return
        }
        loadDocument(url)
    }

    func importDocumentsToShelf(_ urls: [URL]) {
        let supported = RecentDocumentsStore.supportedUniqueURLs(urls)
        guard !supported.isEmpty else { return }

        let importedPaths = RecentDocumentsStore.record(urls: supported)
        let focusPath = importedPaths.first
        if let recentDocumentsPanelController {
            recentDocumentsPanelController.close()
            DispatchQueue.main.async { [weak self] in
                self?.showRecentDocumentsPanel(focusPath: focusPath, priorityPaths: importedPaths)
            }
        } else {
            showRecentDocumentsPanel(focusPath: focusPath)
        }
    }

    func openDocument(_ url: URL) {
        loadDocument(url)
    }

    @objc func openPDFInCurrentDirectory() {
        guard let url = currentFileURL else { return }
        let panel = NSOpenPanel()
        configureOpenPanel(panel)
        panel.allowsMultipleSelection = false
        panel.directoryURL = url.deletingLastPathComponent()
        panel.begin { [weak self] response in
            guard response == .OK, let selectedURL = panel.url else { return }
            self?.loadSelectedDocument(selectedURL)
        }
    }

    func loadSelectedDocument(_ url: URL) {
        guard ReaderDocumentKind.kind(for: url) != nil else {
            NSSound.beep()
            return
        }
        loadDocument(url)
    }
}
