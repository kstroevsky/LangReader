import Cocoa
import PDFKit

extension ReaderWindowController {
    private static let showsRelatedWordFormsDefaultsKey = "reader.showsRelatedWordForms"

    /// Whether the faded-blue markings for related inflected forms are shown.
    /// The exact word the user saved is always marked; this only governs the
    /// other forms the lemma matcher turned up. Persisted, defaults to on.
    var showsRelatedWordForms: Bool {
        get {
            UserDefaults.standard.object(forKey: Self.showsRelatedWordFormsDefaultsKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.showsRelatedWordFormsDefaultsKey)
        }
    }

    func restoreStoredWordAnnotations() {
        guard currentDocumentKind == .pdf else { return }
        pdfVocabularyAnnotationRestoreGeneration += 1
        removeAllVocabularyWordAnnotations()
        highlightedSelectionKeys.removeAll()
        materializeStoredWordAnnotationsForVisiblePages()
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    func restoreStoredWordAnnotationsIncrementally(documentID: String?) {
        guard currentDocumentKind == .pdf,
              currentFileMD5 == documentID else { return }
        restoreStoredWordAnnotations()
    }

    func materializeStoredWordAnnotationsForVisiblePages() {
        addStoredWordAnnotations(storedWordRecords, refineBounds: true)
    }

    func addStoredWordAnnotation(_ record: StoredPDFWordRecord, refineBounds: Bool = true) {
        addPDFVocabularyAnnotation(
            id: record.id,
            pageIndex: record.pageIndex,
            storedBounds: record.bounds.cgRect,
            word: record.occurrenceSurfaceForm,
            isSavedForm: record.matchesSavedSurfaceForm,
            refineBounds: refineBounds,
            invalidateDisplay: true
        )
    }

    func addStoredWordAnnotations(_ records: [StoredPDFWordRecord], refineBounds: Bool = true) {
        let materializationSpan = ReaderPerformance.begin(.visibleHighlightMaterialization)
        defer { ReaderPerformance.end(materializationSpan) }
        let visiblePageIndexes = visiblePDFPageIndexes()
        guard !records.isEmpty, !visiblePageIndexes.isEmpty else { return }
        var didAddAnnotation = false
        for record in records where visiblePageIndexes.contains(record.pageIndex) {
            didAddAnnotation = addPDFVocabularyAnnotation(
                id: record.id,
                pageIndex: record.pageIndex,
                storedBounds: record.bounds.cgRect,
                word: record.occurrenceSurfaceForm,
                isSavedForm: record.matchesSavedSurfaceForm,
                refineBounds: refineBounds,
                invalidateDisplay: false
            ) || didAddAnnotation
        }
        if didAddAnnotation {
            pdfView.setNeedsDisplay(pdfView.bounds)
        }
    }

    func addPendingWordAnnotation(id: String, pageIndex: Int, bounds: CGRect, word: String) {
        // A pending annotation marks the exact selection the user is saving, so
        // it is always the saved form (the lemma matcher runs afterwards).
        addPDFVocabularyAnnotation(
            id: id,
            pageIndex: pageIndex,
            storedBounds: bounds,
            word: word,
            isSavedForm: true,
            refineBounds: true,
            invalidateDisplay: true
        )
    }

    func discardPendingWordAnnotations() {
        restoreStoredWordAnnotations()
    }

    @discardableResult
    private func addPDFVocabularyAnnotation(
        id: String,
        pageIndex: Int,
        storedBounds: CGRect,
        word: String,
        isSavedForm: Bool,
        refineBounds: Bool,
        invalidateDisplay: Bool
    ) -> Bool {
        // Related (non-saved) forms are suppressed when the tumbler is off.
        guard isSavedForm || showsRelatedWordForms else { return false }
        guard let page = pdfView.document?.page(at: pageIndex) else { return false }
        let bounds = refineBounds ? displayBounds(bounds: storedBounds, word: word, page: page) : storedBounds
        let key = wordAnnotationKey(pageIndex: pageIndex, bounds: bounds)
        guard !highlightedSelectionKeys.contains(key) else { return false }
        highlightedSelectionKeys.insert(key)

        let annotation = PDFAnnotation(bounds: wordUnderlineBounds(for: bounds), forType: .highlight, withProperties: nil)
        annotation.color = isSavedForm
            ? vocabularySelectionHighlightColor(for: ReaderTheme.selected)
            : vocabularyVariantHighlightColor(for: ReaderTheme.selected)
        annotation.contents = "leaf-word:\(id)"
        page.addAnnotation(annotation)
        vocabularyState.renderedPDFWordAnnotations.append((page, annotation))
        if invalidateDisplay {
            pdfView.setNeedsDisplay(pdfView.bounds)
        }
        return true
    }

    func removeAllVocabularyWordAnnotations() {
        for rendered in vocabularyState.renderedPDFWordAnnotations {
            rendered.page.removeAnnotation(rendered.annotation)
        }
        vocabularyState.renderedPDFWordAnnotations.removeAll()
    }

    private func visiblePDFPageIndexes() -> Set<Int> {
        guard let document = pdfView.document else { return [] }
        let visiblePages = pdfView.visiblePages.isEmpty
            ? [pdfView.currentPage].compactMap { $0 }
            : pdfView.visiblePages
        return Set(visiblePages.compactMap { page in
            let index = document.index(for: page)
            return index == NSNotFound ? nil : index
        })
    }

    private func wordAnnotationKey(pageIndex: Int, bounds: CGRect) -> String {
        pdfWordRecordStore?.recordKey(pageIndex: pageIndex, bounds: bounds)
            ?? "\(pageIndex):\(Int(bounds.origin.x.rounded())):\(Int(bounds.origin.y.rounded())):\(Int(bounds.width.rounded())):\(Int(bounds.height.rounded()))"
    }

    private func displayBounds(bounds storedBounds: CGRect, word: String, page: PDFPage) -> CGRect {
        precisePDFSelectionBounds(
            page: page,
            originalBounds: storedBounds,
            queryText: word
        ) ?? storedBounds
    }

    func displayBounds(for record: StoredPDFWordRecord, page: PDFPage) -> CGRect {
        displayBounds(bounds: record.bounds.cgRect, word: record.occurrenceSurfaceForm, page: page)
    }

    func refreshStoredWordAnnotationAppearance() {
        restoreStoredWordAnnotations()
    }

    func vocabularySelectionHighlightColor(for theme: ReaderTheme) -> NSColor {
        theme.aiSourceUnderlineColor
    }

    /// A faded version of the saved-word highlight, used for occurrences that are
    /// a different inflected form than the one the user actually saved. Same hue,
    /// lower opacity, so the saved form still reads as the primary mark.
    func vocabularyVariantHighlightColor(for theme: ReaderTheme) -> NSColor {
        let base = vocabularySelectionHighlightColor(for: theme)
        return base.withAlphaComponent(base.alphaComponent * 0.42)
    }

    func wordUnderlineBounds(for bounds: CGRect) -> CGRect {
        let thickness = min(max(bounds.height * 0.08, 2.2), 3.6)
        return CGRect(
            x: bounds.minX,
            y: bounds.minY + max(0, bounds.height * 0.04),
            width: bounds.width,
            height: thickness
        ).insetBy(dx: -0.8, dy: 0)
    }

    func restoreStoredWebWordHighlights(completion: (() -> Void)? = nil) {
        guard currentDocumentKind != .pdf, !storedWebWordRecords.isEmpty else {
            completion?()
            return
        }
        let payload = storedWebWordRecords.map { record -> [String: Any] in
            var item: [String: Any] = [
                "id": record.id,
                "word": record.occurrenceSurfaceForm,
                "context": record.context
            ]
            if let occurrenceIndex = record.occurrenceIndex {
                item["occurrenceIndex"] = occurrenceIndex
            }
            return item
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            completion?()
            return
        }
        webView.evaluateJavaScript("window.leafReaderRestoreWordHighlights(\(json));") { _, _ in
            completion?()
        }
    }

    func markCurrentWebSelectionAsStoredWord(id: String) {
        guard currentDocumentKind != .pdf else { return }
        webView.evaluateJavaScript("window.leafReaderMarkSelectionAsWord && window.leafReaderMarkSelectionAsWord(\(jsStringLiteral(id)));")
    }

    func removeWebWordHighlight(id: String) {
        guard currentDocumentKind != .pdf else { return }
        webView.evaluateJavaScript("window.leafReaderRemoveWordHighlight && window.leafReaderRemoveWordHighlight(\(jsStringLiteral(id)));")
    }

}
