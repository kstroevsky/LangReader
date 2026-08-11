import PDFKit
import LeafReaderCore

extension ReaderWindowController {
    @objc func applyPageFromField() {
        guard currentDocumentKind == .pdf,
              let backend = activePagedReaderBackend,
              backend.pageCount > 0 else {
            updatePageLabel()
            window?.makeFirstResponder(currentDocumentKind == .pdf ? pdfView : webView)
            return
        }

        guard let requestedPage = ReaderFieldInput.pageNumber(from: pageLabel.stringValue),
              let targetIndex = ReaderFieldInput.pageIndex(
                  fromTyped: requestedPage,
                  pageCount: backend.pageCount
              ) else {
            updatePageLabel()
            window?.makeFirstResponder(pdfView)
            return
        }

        guard backend.go(toPage: targetIndex), let page = pdfView.currentPage else {
            updatePageLabel()
            window?.makeFirstResponder(pdfView)
            return
        }

        clearAISelectionForNavigation()
        documentSession.position.lastPageIndex = targetIndex
        scrollPageToTop(page)
        updatePageLabel()
        saveSession()
        window?.makeFirstResponder(pdfView)
    }

    @objc func prevPage() {
        markReaderInteraction()
        clearAISelectionForNavigation()
        guard currentDocumentKind == .pdf else {
            scrollWebPage(direction: -1)
            return
        }
        turnPDFPage(direction: .previous)
    }

    @objc func nextPage() {
        markReaderInteraction()
        clearAISelectionForNavigation()
        guard currentDocumentKind == .pdf else {
            scrollWebPage(direction: 1)
            return
        }
        turnPDFPage(direction: .next)
    }

    func scrollWebPage(direction: Int) {
        let sign = direction < 0 ? "-" : ""
        webView.evaluateJavaScript("window.scrollBy({top: \(sign)Math.max(240, window.innerHeight * 0.86), behavior: 'smooth'});")
    }

    @objc func goToCover() {
        clearAISelectionForNavigation()
        guard currentDocumentKind == .pdf else {
            webView.evaluateJavaScript("""
            (() => {
              const cover = document.querySelector('section.reader-section[data-leaf-cover="true"]') || document.querySelector('section.reader-section');
              if (cover) {
                cover.scrollIntoView({behavior:'smooth', block:'start'});
              } else {
                window.scrollTo({top:0, behavior:'smooth'});
              }
            })();
            """)
            return
        }
        guard activePagedReaderBackend?.go(toPage: 0) == true,
              let firstPage = pdfView.currentPage else { return }
        scrollPageToTop(firstPage)
        updatePageLabel()
        saveSession()
    }

    @objc func goToFarthestReadingPosition() {
        markReaderInteraction()
        clearAISelectionForNavigation()
        guard currentDocumentKind == .pdf else {
            let storedProgress = sessionStore.loadFarthestWebProgress()
            if let zoomPercent = storedProgress?.zoomPercent {
                documentSession.web.zoomPercent = zoomPercent
                updateZoomLabel()
                applyWebZoomToPage()
            }
            jumpToWebProgress(storedProgress?.scrollProgress ?? webScrollProgress, animated: true)
            return
        }
        guard let backend = activePagedReaderBackend, backend.pageCount > 0 else { return }
        let storedProgress = sessionStore.loadFarthestPDFProgress()
        let targetIndex = min(max(storedProgress?.pageIndex ?? backend.currentPageIndex ?? 0, 0), backend.pageCount - 1)
        guard backend.go(toPage: targetIndex), let page = pdfView.currentPage else { return }
        documentSession.position.lastPageIndex = targetIndex
        if let storedProgress, ReaderSessionPolicy.isRestorablePDFScale(storedProgress.scale) {
            applyReadablePDFScale(storedProgress.scale)
        }
        if let anchorPoint = storedProgress?.anchorPoint {
            restorePDFViewportAnchor(page: page, point: anchorPoint)
        } else {
            scrollPageToTop(page)
        }
        updatePageLabel()
        saveSession()
        window?.makeFirstResponder(pdfView)
    }

    func jumpToWebProgress(_ progressValue: Double, animated: Bool) {
        let progress = min(1, max(0, progressValue))
        webScrollProgress = progress
        updateWebProgressLabel(progress)
        scrollWebToProgress(progress, animated: animated)
        saveSession()
        window?.makeFirstResponder(webView)
    }

    func scrollWebToProgress(_ progress: Double, animated: Bool) {
        let behavior = animated ? "smooth" : "auto"
        let script = """
        (() => {
          const progress = \(progress);
          const scroll = () => {
            const scrollHeight = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
            window.scrollTo({ top: scrollHeight * progress, behavior: '\(behavior)' });
          };
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', () => requestAnimationFrame(scroll), { once: true });
          } else {
            requestAnimationFrame(() => requestAnimationFrame(scroll));
          }
        })();
        """
        webView.evaluateJavaScript(script)
    }


    private enum PDFPageDirection {
        case previous
        case next
    }


    private func turnPDFPage(direction: PDFPageDirection) {
        guard let backend = activePagedReaderBackend, backend.pageCount > 0 else { return }
        let currentIndex = currentPDFViewportAnchor()?.pageIndex ?? backend.currentPageIndex ?? 0
        let targetIndex: Int
        switch direction {
        case .previous:
            targetIndex = currentIndex - 1
        case .next:
            targetIndex = currentIndex + 1
        }
        guard targetIndex >= 0,
              targetIndex < backend.pageCount,
              backend.go(toPage: targetIndex),
              let page = pdfView.currentPage else {
            updatePageLabel()
            saveSession()
            return
        }
        scrollPageToTop(page)
        documentSession.position.lastPageIndex = targetIndex
        updatePageLabel()
        saveSession()
    }

    /// Scrolls so the top of `page` sits at the top of the viewport.
    ///
    /// Both Prev and Next land here: a page turn shows the start of the page it
    /// lands on, in either direction. `PDFDestination` places the point it is
    /// given at the top of the visible area, so the page's top edge
    /// (`bounds.maxY` in PDF space, where y grows upward) is exactly that point.
    func scrollPageToTop(_ page: PDFPage) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  self.pdfView.document?.index(for: page) != NSNotFound else {
                return
            }
            let bounds = page.bounds(for: self.pdfView.displayBox)
            let destination = PDFDestination(page: page, at: NSPoint(x: bounds.minX, y: bounds.maxY))
            self.pdfView.go(to: destination)
            self.updatePageLabel()
        }
    }

    @objc func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    @objc func pageChanged() {
        handlePDFPageChange()
    }

    func handlePDFPageChange() {
        markReaderInteraction()
        hideSelectionToolbar()
        materializeStoredWordAnnotationsForVisiblePages()
        let newPageIndex = currentPageIndex()
        guard newPageIndex != documentSession.position.lastPageIndex else {
            updatePageLabel()
            saveSession()
            return
        }
        documentSession.position.lastPageIndex = newPageIndex
        updatePageLabel()
        saveSession()
        if !isReadAloudActive {
            scheduleDocumentEmbeddingWarmup(priorityPageIndex: newPageIndex)
        }
    }

}
