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
        for record in storedWordRecords {
            addPDFVocabularyAnnotation(
                id: record.id,
                pageIndex: record.pageIndex,
                storedBounds: record.bounds.cgRect,
                word: record.occurrenceSurfaceForm,
                isSavedForm: record.matchesSavedSurfaceForm,
                refineBounds: true,
                invalidateDisplay: false
            )
        }
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    func restoreStoredWordAnnotationsIncrementally(documentID: String?) {
        guard currentDocumentKind == .pdf else { return }
        pdfVocabularyAnnotationRestoreGeneration += 1
        let generation = pdfVocabularyAnnotationRestoreGeneration
        removeAllVocabularyWordAnnotations()
        highlightedSelectionKeys.removeAll()
        restoreStoredWordAnnotationBatch(
            documentID: documentID,
            generation: generation,
            startIndex: 0
        )
    }

    private func restoreStoredWordAnnotationBatch(
        documentID: String?,
        generation: Int,
        startIndex: Int
    ) {
        guard currentDocumentKind == .pdf,
              currentFileMD5 == documentID,
              pdfVocabularyAnnotationRestoreGeneration == generation else { return }
        let endIndex = min(startIndex + 20, storedWordRecords.count)
        guard startIndex < endIndex else { return }
        for record in storedWordRecords[startIndex..<endIndex] {
            addPDFVocabularyAnnotation(
                id: record.id,
                pageIndex: record.pageIndex,
                storedBounds: record.bounds.cgRect,
                word: record.occurrenceSurfaceForm,
                isSavedForm: record.matchesSavedSurfaceForm,
                refineBounds: true,
                invalidateDisplay: false
            )
        }
        pdfView.setNeedsDisplay(pdfView.bounds)
        guard endIndex < storedWordRecords.count else { return }
        DispatchQueue.main.async { [weak self] in
            self?.restoreStoredWordAnnotationBatch(
                documentID: documentID,
                generation: generation,
                startIndex: endIndex
            )
        }
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
        guard !records.isEmpty else { return }
        for record in records {
            addPDFVocabularyAnnotation(
                id: record.id,
                pageIndex: record.pageIndex,
                storedBounds: record.bounds.cgRect,
                word: record.occurrenceSurfaceForm,
                isSavedForm: record.matchesSavedSurfaceForm,
                refineBounds: refineBounds,
                invalidateDisplay: false
            )
        }
        pdfView.setNeedsDisplay(pdfView.bounds)
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

    private func addPDFVocabularyAnnotation(
        id: String,
        pageIndex: Int,
        storedBounds: CGRect,
        word: String,
        isSavedForm: Bool,
        refineBounds: Bool,
        invalidateDisplay: Bool
    ) {
        // Related (non-saved) forms are suppressed when the tumbler is off.
        guard isSavedForm || showsRelatedWordForms else { return }
        guard let page = pdfView.document?.page(at: pageIndex) else { return }
        let bounds = refineBounds ? displayBounds(bounds: storedBounds, word: word, page: page) : storedBounds
        let key = wordAnnotationKey(pageIndex: pageIndex, bounds: bounds)
        guard !highlightedSelectionKeys.contains(key) else { return }
        highlightedSelectionKeys.insert(key)

        let annotation = PDFAnnotation(bounds: wordUnderlineBounds(for: bounds), forType: .highlight, withProperties: nil)
        annotation.color = isSavedForm
            ? vocabularySelectionHighlightColor(for: ReaderTheme.selected)
            : vocabularyVariantHighlightColor(for: ReaderTheme.selected)
        annotation.contents = "leaf-word:\(id)"
        page.addAnnotation(annotation)
        if invalidateDisplay {
            pdfView.setNeedsDisplay(pdfView.bounds)
        }
    }

    private func removeAllVocabularyWordAnnotations() {
        guard let document = pdfView.document else { return }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations where annotation.contents?.hasPrefix("leaf-word:") == true {
                page.removeAnnotation(annotation)
            }
        }
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
