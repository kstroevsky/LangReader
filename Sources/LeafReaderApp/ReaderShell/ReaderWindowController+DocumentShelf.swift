import Cocoa
import LeafReaderCore

extension ReaderWindowController {
    @objc func showRecentDocuments() {
        showRecentDocumentsPanel(focusPath: nil, priorityPaths: [])
    }

    func showRecentDocumentsPanel(focusPath: String?, priorityPaths: [String] = []) {
        let openSpan = ReaderPerformance.begin(.shelfOpen)
        defer { ReaderPerformance.end(openSpan) }
        let items = sortedRecentDocuments(priorityPaths: priorityPaths)
        guard !items.isEmpty else {
            NSSound.beep()
            return
        }
        let controller = RecentDocumentsPanelController()
        recentDocumentsPanelController = controller
        controller.show(
            items: items,
            attachedTo: window,
            focusPath: focusPath,
            onOpen: { [weak self] path in
                self?.loadDocument(URL(fileURLWithPath: path))
            },
            onClear: { [weak self] in
                self?.unloadCurrentDocumentForShelfRemoval()
                RecentDocumentsStore.clear()
            },
            onRemoveItem: { [weak self] path, options in
                self?.removeShelfItem(
                    path: path,
                    clearVectorCache: options.clearVectorCache,
                    clearWordRecords: options.clearWordRecords,
                    clearAIData: options.clearAIData
                )
            },
            onClearVectorCache: { [weak self] path in
                self?.clearVectorCacheForShelfItem(path: path)
            },
            onClearWordRecords: { [weak self] path in
                self?.clearWordRecordsForShelfItem(path: path)
            },
            onClearAIData: { [weak self] path in
                self?.clearAIDataForShelfItem(path: path)
            },
            onImport: { [weak self] urls in
                guard let self else { return }
                self.importDocumentsToShelf(urls)
            },
            onClose: { [weak self] in
                self?.recentDocumentsPanelController = nil
            }
        )
    }

    func sortedRecentDocuments(priorityPaths: [String]) -> [RecentDocumentItem] {
        let items = RecentDocumentsStore.load()
        guard !priorityPaths.isEmpty else {
            return items.sorted { lhs, rhs in
                if lhs.openedAt != rhs.openedAt {
                    return lhs.openedAt > rhs.openedAt
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }

        var priorityIndex: [String: Int] = [:]
        for (index, path) in priorityPaths.enumerated() where priorityIndex[path] == nil {
            priorityIndex[path] = index
        }
        return items.sorted { lhs, rhs in
            let lhsPriority = priorityIndex[lhs.path]
            let rhsPriority = priorityIndex[rhs.path]
            switch (lhsPriority, rhsPriority) {
            case let (.some(left), .some(right)):
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                if lhs.openedAt != rhs.openedAt {
                    return lhs.openedAt > rhs.openedAt
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    func removeShelfItem(path: String, clearVectorCache: Bool, clearWordRecords: Bool, clearAIData: Bool) {
        let documentID = fileMD5(for: URL(fileURLWithPath: path))
        if currentFileURL?.path == path {
            unloadCurrentDocumentForShelfRemoval()
        }
        if let documentID {
            ReaderSessionStore(fileMD5: documentID).clearProgress()
            clearStoredEmbeddingControlState(documentID: documentID)
        }
        if clearVectorCache {
            clearVectorCacheForShelfItem(path: path)
        }
        if clearWordRecords {
            clearWordRecordsForShelfItem(path: path)
        }
        if clearAIData, let documentID {
            clearAIDataForDocument(documentID: documentID, wasCurrentDocument: currentFileMD5 == documentID)
            if !clearWordRecords {
                clearWordRecordsForShelfItem(path: path)
            }
        }
        RecentDocumentsStore.remove(path: path)
    }

    func unloadCurrentDocumentForShelfRemoval() {
        guard currentFileURL != nil else { return }
        stopReadAloudImmediately()
        saveCurrentAIConversationBeforeDocumentChange()
        saveSession()
        resetEmbeddingStateForDocumentChange()

        documentSession.unload()
        documentPresentationState.resetForDocumentChange()
        invalidateDocumentAgentIndex()
        clearDocumentContentViewsForUnload()
        resetCurrentDocumentRuntimeState()
        resetEmptyDocumentChrome()
    }

    private func clearDocumentContentViewsForUnload() {
        pdfView.document = nil
        pdfView.isHidden = false
        pdfDimOverlay.isHidden = true
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        webView.isHidden = true
    }

    private func resetCurrentDocumentRuntimeState() {
        pdfWordRecordStore = nil
        webWordRecordStore = nil
        aiConversationStore = nil
        loadedAIConversation = nil
        clearSearchState()
        pendingPDFWordRecords.removeAll()
        pendingWebWordRecords.removeAll()
        storedWordRecords.removeAll()
        storedWebWordRecords.removeAll()
        highlightedSelectionKeys.removeAll()
        currentVocabularyExportRecords.removeAll()
    }

    private func resetEmptyDocumentChrome() {
        aiPanel.loadLinkedWordBubbles([])
        aiPanel.clearSelectedText()
        setDocumentTitle(AppIdentity.displayName)
        coverImageView.image = nil
        refreshChromeState(presentation: .empty)
        pageLabel.stringValue = AppText.noPDF
        updatePageLabelTextColor()
        updateZoomLabel()
        updateEmbeddingControlButtons()
        applyReaderTheme()
    }

    func clearVectorCacheForShelfItem(path: String) {
        guard let documentID = fileMD5(for: URL(fileURLWithPath: path)) else {
            NSSound.beep()
            return
        }
        clearStoredEmbeddingControlState(documentID: documentID)
        let store = pdfEmbeddingStore
        embeddingStoreQueue.async {
            store?.deleteDocument(documentID: documentID)
        }
        if currentFileMD5 == documentID {
            invalidateEmbeddingBackfill()
            invalidateDocumentAgentIndex()
            bottomBarModel.embeddingStatusText = AppText.localized("AI 分析数据：已清除当前书", "AI analysis data: current book cleared")
            bottomBarModel.embeddingStatusVisible = true
            updateEmbeddingControlButtons()
        }
    }

    func clearWordRecordsForShelfItem(path: String) {
        guard let documentID = fileMD5(for: URL(fileURLWithPath: path)) else {
            NSSound.beep()
            return
        }
        if currentFileMD5 == documentID {
            clearCurrentBookWordRecords()
            return
        }
        PDFWordRecordStore(fileMD5: documentID).save([])
        WebWordRecordStore(fileMD5: documentID).save([])
        vocabularyLibraryWindowController.scheduleReload()
    }

    func clearAIDataForShelfItem(path: String) {
        guard let documentID = fileMD5(for: URL(fileURLWithPath: path)) else {
            NSSound.beep()
            return
        }
        clearAIDataForDocument(documentID: documentID, wasCurrentDocument: currentFileMD5 == documentID)
        clearWordRecordsForShelfItem(path: path)
    }

    func clearAIDataForDocument(documentID: String, wasCurrentDocument: Bool) {
        clearStoredEmbeddingControlState(documentID: documentID)
        if wasCurrentDocument {
            aiConversationSaveTask.cancel()
            pendingAIConversationToSave = nil
            clearAISourceUnderlines()
            aiPanel.loadLinkedWordBubbles([])
            aiPanel.clearSelectedText()
        }
        AIConversationStore(fileMD5: documentID).clear()
    }
}
