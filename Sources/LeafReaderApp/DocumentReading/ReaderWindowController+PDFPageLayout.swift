import PDFKit

extension ReaderWindowController {
    @objc func togglePDFPageLayout() {
        guard currentDocumentKind == .pdf else { return }
        let nextValue = !isPDFTwoPageModeEnabled()
        setPDFTwoPageModeEnabled(nextValue)
        applyPDFPageLayout(animated: true)
        saveSession()
        window?.makeFirstResponder(pdfView)
    }

    func applyPDFPageLayout(animated: Bool) {
        guard currentDocumentKind == .pdf else { return }
        let currentPage = pdfView.currentPage
        let currentPageIndex = currentPage.flatMap { pdfView.document?.index(for: $0) }
        let currentDestination = currentPage.map { PDFDestination(page: $0, at: pdfView.convert(pdfView.bounds.origin, to: $0)) }
        let currentScaleFactor = pdfView.scaleFactor
        let isTwoPage = isPDFTwoPageModeEnabled()
        let targetMode = PDFPageLayoutPolicy.displayMode(isTwoPage: isTwoPage)
        let needsDisplayModeChange = pdfView.displayMode != targetMode
        let needsBookModeChange = pdfView.displaysAsBook
        guard needsDisplayModeChange || needsBookModeChange else {
            updatePDFPageLayoutButton()
            return
        }
        topBarModel.pageLayoutEnabled = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.08 : 0
            pdfView.autoScales = false
            if needsBookModeChange {
                pdfView.displaysAsBook = false
            }
            if needsDisplayModeChange {
                pdfView.displayMode = targetMode
            }
            pdfView.scaleFactor = currentScaleFactor
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let currentPage,
               let currentPageIndex,
               self.pdfView.document?.index(for: self.pdfView.currentPage ?? PDFPage()) != currentPageIndex {
                self.pdfView.go(to: currentPage)
            }
            if let currentDestination {
                self.pdfView.go(to: currentDestination)
            }
            self.pdfView.scaleFactor = currentScaleFactor
            self.topBarModel.pageLayoutEnabled = true
            self.updateZoomLabel()
        }
        updatePDFPageLayoutButton()
    }

    func updatePDFPageLayoutButton() {
        topBarModel.pageLayoutIsTwoPage = isPDFTwoPageModeEnabled()
    }

    func isPDFTwoPageModeEnabled() -> Bool {
        let defaults = UserDefaults.standard
        let key = pdfTwoPageModeDefaultsKeyForCurrentBook()
        if defaults.object(forKey: key) != nil {
            return defaults.bool(forKey: key)
        }
        return defaults.bool(forKey: Self.pdfTwoPageModeDefaultsKey)
    }

    func setPDFTwoPageModeEnabled(_ enabled: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(enabled, forKey: pdfTwoPageModeDefaultsKeyForCurrentBook())
        defaults.set(enabled, forKey: Self.pdfTwoPageModeDefaultsKey)
    }

    func pdfTwoPageModeDefaultsKeyForCurrentBook() -> String {
        guard let currentFileMD5, !currentFileMD5.isEmpty else {
            return Self.pdfTwoPageModeDefaultsKey
        }
        return "\(Self.pdfTwoPageModeDefaultsKey).\(currentFileMD5)"
    }
}
