import Cocoa
import PDFKit
import WebKit

extension ReaderWindowController {
    @objc func showSearchOverlay() {
        readerPresentation.showSearch()
        searchOverlay.isHidden = !readerPresentation.isSearchVisible
        window?.makeFirstResponder(searchOverlay.searchField)
    }

    func hideSearchOverlay() {
        readerPresentation.hideSearch()
        searchOverlay.isHidden = readerPresentation.isSearchVisible
        window?.makeFirstResponder(currentDocumentKind == .pdf ? pdfView : webView)
    }

    func performSearch(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        readerPresentation.setSearchQuery(query)
        guard !query.isEmpty else {
            clearSearchState()
            clearPDFSelectionState()
            pdfReaderAdapter.clearSelection()
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
            searchResults = document.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])
            searchCursor.setTotal(searchResults.count)
        case .advance:
            searchCursor.advance()
        }

        showCurrentSearchResult()
    }

    func clearSearchState() {
        searchResults.removeAll()
        searchCursor.clear()
        searchOverlay.setResultText("")
    }

    func goToPreviousSearchResult() {
        guard currentDocumentKind == .pdf else {
            performWebSearch(searchOverlay.searchField.stringValue, backwards: true)
            return
        }
        guard !searchResults.isEmpty else {
            performSearch(searchOverlay.searchField.stringValue)
            return
        }
        searchCursor.retreat()
        showCurrentSearchResult()
    }

    func goToNextSearchResult() {
        guard currentDocumentKind == .pdf else {
            performWebSearch(searchOverlay.searchField.stringValue, backwards: false)
            return
        }
        guard !searchResults.isEmpty else {
            performSearch(searchOverlay.searchField.stringValue)
            return
        }
        searchCursor.advance()
        showCurrentSearchResult()
    }

    func showCurrentSearchResult() {
        guard !searchResults.isEmpty else {
            searchOverlay.setResultText("0 / 0")
            clearPDFSelectionState()
            pdfReaderAdapter.clearSelection()
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
        let overlayClearance = searchOverlay.isHidden ? CGFloat(64) : CGFloat(150)
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
