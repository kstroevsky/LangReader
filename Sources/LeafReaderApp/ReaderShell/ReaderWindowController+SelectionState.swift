import Cocoa
import PDFKit
import LeafReaderCore

extension ReaderWindowController {
    func clearAISelectionForNavigation() {
        clearPDFSelectionState()
        clearWebSelectionState()
        aiPanel.clearSelectedText()
        hideSelectionToolbar()
        clearReaderDocumentSelection()
    }

    func clearReaderSelectionForBubbleSelection() {
        clearPDFSelectionState()
        clearWebSelectionState()
        hideSelectionToolbar()
        clearReaderDocumentSelection()
    }

    @objc func selectionChanged() {
        guard currentDocumentKind == .pdf else { return }
        guard Date() >= suppressSearchSelectionForAIUntil else {
            clearSearchSelectionForAI()
            return
        }

        let selection = pdfView.currentSelection
        let text = selection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let selectedText = text.count > 1 ? text : ""
        var readerSelection = selectionState
        readerSelection.pdfSelectedText = selectedText
        selectionState = readerSelection
        updateAISelection(explicitText: selectedText)

        if selectedText.isEmpty {
            hideSelectionToolbar()
        } else if let selection {
            showSelectionToolbarForPDFSelection(selection, text: selectedText)
        }
    }

    func handleWebSelectionChanged(body: Any) {
        guard Date() >= suppressSearchSelectionForAIUntil else {
            clearSearchSelectionForAI()
            return
        }

        let selection = webSelection(from: body)
        setWebSelection(
            text: selection.text,
            context: selection.context,
            occurrenceIndex: selection.occurrenceIndex,
            rect: selection.rect
        )
        let selectedText = selectionState.webSelectedText
        updateAISelection(explicitText: selectedText)

        if selectedText.isEmpty {
            hideSelectionToolbar()
        } else {
            showSelectionToolbarForWebSelection(
                rect: documentSession.selectionPresentation.anchorRect,
                text: selectedText
            )
        }
    }

    func setWebSelectionFromVisibleText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        setWebSelection(text: trimmed, context: trimmed, occurrenceIndex: nil, rect: nil)
        aiPanel.setSelectedText(selectionState.webSelectedText)
    }

    private func updateAISelection(explicitText: String) {
        let selectedText = ReaderAIContextResolver(
            explicitSelection: explicitText,
            readAloudSelection: currentReadAloudSelectionTextForAI()
        ).preferredSelectionText
        aiPanel.setSelectedText(selectedText)
    }

    func clearWebSelectionState() {
        var selection = selectionState
        selection.webSelectedText = ""
        selection.webSelectionContext = ""
        selection.webSelectionOccurrenceIndex = nil
        selectionState = selection

        var presentation = documentSession.selectionPresentation
        presentation.anchorRect = nil
        documentSession.selectionPresentation = presentation
    }

    private func clearReaderDocumentSelection() {
        activeReaderBackend?.clearSelection()
        if currentDocumentKind != .pdf {
            clearWebSearchSelection()
        }
    }

    private func setWebSelection(text: String, context: String, occurrenceIndex: Int?, rect: NSRect?) {
        var selection = selectionState
        selection.webSelectedText = text.count > 1 ? text : ""
        selection.webSelectionContext = selection.webSelectedText.isEmpty ? "" : context
        selection.webSelectionOccurrenceIndex = selection.webSelectedText.isEmpty ? nil : occurrenceIndex
        selectionState = selection

        var presentation = documentSession.selectionPresentation
        presentation.anchorRect = selection.webSelectedText.isEmpty ? nil : rect
        documentSession.selectionPresentation = presentation
    }

    private func webSelection(from body: Any) -> (text: String, context: String, occurrenceIndex: Int?, rect: NSRect?) {
        if let payload = body as? [String: Any] {
            let text = (payload["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let context = (payload["context"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (
                text: text,
                context: context,
                occurrenceIndex: payload["occurrenceIndex"] as? Int,
                rect: webSelectionRect(from: payload["rect"])
            )
        }

        let text = (body as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (text: text, context: "", occurrenceIndex: nil, rect: nil)
    }
}
