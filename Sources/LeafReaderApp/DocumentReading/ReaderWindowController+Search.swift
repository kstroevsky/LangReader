import Cocoa
import PDFKit
import WebKit

extension ReaderWindowController {
    @objc func showSearchOverlay() {
        mutateReaderPresentation { $0.showSearch() }
        window?.makeFirstResponder(searchOverlay.searchField)
    }

    func hideSearchOverlay() {
        mutateReaderPresentation { $0.hideSearch() }
        window?.makeFirstResponder(currentDocumentKind == .pdf ? pdfView : webView)
    }

    func performSearch(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        mutateReaderPresentation { $0.setSearchQuery(query) }
        guard !query.isEmpty else {
            clearSearchState()
            clearPDFSelectionState()
            activeReaderBackend?.clearSelection()
            clearWebSearchSelection()
            clearSearchSelectionForAI()
            return
        }
        guard currentDocumentKind == .pdf else {
            performWebSearch(query, backwards: false)
            return
        }
        guard let document = pdfView.document else {
            searchOverlay.setResultText("0 / 0")
            return
        }

        switch searchCursor.submit(query: query) {
        case .needsSearch:
            beginPDFSearch(query, document: document)
            return
        case .advance:
            searchCursor.advance()
        }

        showCurrentSearchResult()
    }

    func clearSearchState() {
        activePDFSearchDocument?.cancelFindString()
        activePDFSearchDocument = nil
        activePDFSearchQuery = ""
        activePDFSearchStartedAt = nil
        searchResults.removeAll()
        searchCursor.clear()
        searchOverlay.setResultText("")
    }

    private func beginPDFSearch(_ query: String, document: PDFDocument) {
        if !didRegisterPDFSearchObservers {
            didRegisterPDFSearchObservers = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pdfDocumentDidFindMatch(_:)),
                name: .PDFDocumentDidFindMatch,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pdfDocumentDidEndFind(_:)),
                name: .PDFDocumentDidEndFind,
                object: nil
            )
        }
        activePDFSearchDocument?.cancelFindString()
        activePDFSearchDocument = document
        activePDFSearchQuery = query
        activePDFSearchStartedAt = ProcessInfo.processInfo.systemUptime
        searchResults.removeAll(keepingCapacity: true)
        searchCursor.setTotal(0)
        searchOverlay.setResultText("0 / …")
        document.beginFindString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])
    }

    @objc private func pdfDocumentDidFindMatch(_ notification: Notification) {
        guard let document = notification.object as? PDFDocument,
              document === activePDFSearchDocument,
              document === pdfView.document,
              activePDFSearchQuery == searchCursor.query,
              let selection = notification.userInfo?[PDFDocumentFoundSelectionKey] as? PDFSelection else { return }
        let shouldShowFirstResult = searchResults.isEmpty
        searchResults.append(selection)
        searchCursor.adoptOneBased(index: searchCursor.index + 1, total: searchResults.count)
        if shouldShowFirstResult {
            showCurrentSearchResult()
        } else {
            searchOverlay.setResultText(searchCursor.resultText)
        }
    }

    @objc private func pdfDocumentDidEndFind(_ notification: Notification) {
        guard let document = notification.object as? PDFDocument,
              document === activePDFSearchDocument,
              document === pdfView.document,
              activePDFSearchQuery == searchCursor.query,
              !document.isFinding else { return }
        if let startedAt = activePDFSearchStartedAt {
            ReaderPerformance.record(
                .pdfSearch,
                milliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1000
            )
            activePDFSearchStartedAt = nil
        }
        searchCursor.adoptOneBased(index: searchCursor.index + 1, total: searchResults.count)
        if searchResults.isEmpty {
            showCurrentSearchResult()
        } else {
            searchOverlay.setResultText(searchCursor.resultText)
        }
    }

    func goToPreviousSearchResult() {
        guard currentDocumentKind == .pdf else {
            performWebSearch(readerPresentation.searchQuery, backwards: true)
            return
        }
        guard !searchResults.isEmpty else {
            performSearch(readerPresentation.searchQuery)
            return
        }
        searchCursor.retreat()
        showCurrentSearchResult()
    }

    func goToNextSearchResult() {
        guard currentDocumentKind == .pdf else {
            performWebSearch(readerPresentation.searchQuery, backwards: false)
            return
        }
        guard !searchResults.isEmpty else {
            performSearch(readerPresentation.searchQuery)
            return
        }
        searchCursor.advance()
        showCurrentSearchResult()
    }

    func showCurrentSearchResult() {
        guard !searchResults.isEmpty else {
            searchOverlay.setResultText("0 / 0")
            clearPDFSelectionState()
            activeReaderBackend?.clearSelection()
            clearSearchSelectionForAI()
            return
        }

        let selection = searchResults[min(searchCursor.index, searchResults.count - 1)]
        beginSuppressingSearchSelectionForAI()
        pdfView.setCurrentSelection(selection, animate: true)
        let pageIndex = goToVisibleSearchSelection(selection)
        if let pageIndex {
            documentSession.position.lastPageIndex = pageIndex
        }
        updatePageLabel()
        saveSession()
        searchOverlay.setResultText(searchCursor.resultText)
        clearSearchSelectionForAI()
    }

    @discardableResult
    func goToVisibleSearchSelection(_ selection: PDFSelection) -> Int? {
        guard let page = selection.pages.first else {
            pdfView.go(to: selection)
            return currentPageIndex()
        }

        let selectionBounds = selection.bounds(for: page)
        guard !selectionBounds.isEmpty else {
            pdfView.go(to: selection)
            return currentPageIndex()
        }

        pdfView.go(to: page)
        let pageBounds = page.bounds(for: pdfView.displayBox)
        let overlayClearance = readerPresentation.projection.searchOverlayClearance
        let yOffset = overlayClearance / max(pdfView.scaleFactor, 0.1)
        let destinationY = min(pageBounds.maxY, selectionBounds.maxY + yOffset)
        let destination = PDFDestination(
            page: page,
            at: NSPoint(x: max(pageBounds.minX, selectionBounds.minX), y: destinationY)
        )
        pdfView.go(to: destination)
        return pdfView.document?.index(for: page)
    }

    func performWebSearch(_ rawQuery: String, backwards: Bool) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        mutateReaderPresentation { $0.setSearchQuery(query) }
        guard !query.isEmpty else {
            clearSearchState()
            clearWebSearchSelection()
            clearSearchSelectionForAI()
            return
        }

        beginSuppressingSearchSelectionForAI()
        let escapedQuery = jsStringLiteral(query)
        let reset = searchCursor.submit(query: query) == .needsSearch
        let script = """
        (() => {
          const query = \(escapedQuery);
          if (window.leafReaderSearch) {
            return window.leafReaderSearch(query, \(backwards ? "-1" : "1"), \(reset ? "true" : "false"));
          }
          const found = window.find(query, false, \(backwards ? "true" : "false"), true, false, true, false);
          return { index: found ? 1 : 0, total: found ? 1 : 0 };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            let payload = result as? [String: Any]
            let index = payload?["index"] as? Int ?? 0
            let total = payload?["total"] as? Int ?? 0
            self?.searchCursor.adoptOneBased(index: index, total: total)
            self?.searchOverlay.setResultText(self?.searchCursor.resultText ?? "0 / 0")
            self?.clearSearchSelectionForAI()
        }
    }

    func beginSuppressingSearchSelectionForAI() {
        suppressSearchSelectionForAIUntil = Date().addingTimeInterval(1.2)
    }

    func clearSearchSelectionForAI() {
        clearPDFSelectionState()
        clearWebSelectionState()
        aiPanel.clearSelectedText()
        hideSelectionToolbar()
    }

    func clearWebSearchSelection() {
        webView?.evaluateJavaScript("""
            if (window.leafReaderClearSelection) {
              window.leafReaderClearSelection();
            } else if (window.getSelection) {
              window.getSelection().removeAllRanges();
            }
            if (window.leafReaderClearSearchHighlights) {
              window.leafReaderClearSearchHighlights();
            }
        """)
    }

    func jsStringLiteral(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [text]),
              let encoded = String(data: data, encoding: .utf8),
              encoded.count >= 2 else {
            return "\"\""
        }
        return String(encoded.dropFirst().dropLast())
    }
}
