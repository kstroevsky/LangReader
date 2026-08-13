import Foundation
import LeafReaderCore

extension ReaderWindowController {
    @objc func applyPageFromField() {
        guard currentDocumentKind == .pdf,
              let backend = activePagedReaderBackend,
              backend.pageCount > 0 else {
            updatePageLabel()
            activeReaderBackend?.focus()
            return
        }

        guard let requestedPage = ReaderFieldInput.pageNumber(from: pageLabel.stringValue),
              let targetIndex = ReaderFieldInput.pageIndex(
                  fromTyped: requestedPage,
                  pageCount: backend.pageCount
              ) else {
            updatePageLabel()
            backend.focus()
            return
        }

        guard backend.go(toPage: targetIndex),
              backend.scrollToTop(ofPage: targetIndex) else {
            updatePageLabel()
            backend.focus()
            return
        }

        clearAISelectionForNavigation()
        documentSession.position.lastPageIndex = targetIndex
        updatePageLabel()
        saveSession()
        backend.focus()
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
        activeContinuousReaderBackend?.scrollByPage(direction < 0 ? .previous : .next)
    }

    @objc func goToCover() {
        clearAISelectionForNavigation()
        guard currentDocumentKind == .pdf else {
            activeContinuousReaderBackend?.scrollToCover()
            return
        }
        guard let backend = activePagedReaderBackend,
              backend.go(toPage: 0),
              backend.scrollToTop(ofPage: 0) else { return }
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
        guard backend.go(toPage: targetIndex) else { return }
        documentSession.position.lastPageIndex = targetIndex
        if let storedProgress, ReaderSessionPolicy.isRestorablePDFScale(storedProgress.scale) {
            applyReadablePDFScale(storedProgress.scale)
        }
        if let anchorPoint = storedProgress?.anchorPoint {
            _ = backend.restoreViewportAnchor(
                ReaderPagedViewportAnchor(pageIndex: targetIndex, point: anchorPoint)
            )
        } else {
            _ = backend.scrollToTop(ofPage: targetIndex)
        }
        updatePageLabel()
        saveSession()
        backend.focus()
    }

    func jumpToWebProgress(_ progressValue: Double, animated: Bool) {
        let progress = min(1, max(0, progressValue))
        webScrollProgress = progress
        updateWebProgressLabel(progress)
        scrollWebToProgress(progress, animated: animated)
        saveSession()
        activeContinuousReaderBackend?.focus()
    }

    func scrollWebToProgress(_ progress: Double, animated: Bool) {
        activeContinuousReaderBackend?.scroll(toProgress: progress, animated: animated)
    }


    private enum PDFPageDirection {
        case previous
        case next
    }


    private func turnPDFPage(direction: PDFPageDirection) {
        guard let backend = activePagedReaderBackend, backend.pageCount > 0 else { return }
        let currentIndex = backend.viewportAnchor?.pageIndex ?? backend.currentPageIndex ?? 0
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
              backend.scrollToTop(ofPage: targetIndex) else {
            updatePageLabel()
            saveSession()
            return
        }
        documentSession.position.lastPageIndex = targetIndex
        updatePageLabel()
        saveSession()
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
