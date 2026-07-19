import Cocoa
import PDFKit

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
        currentPDFSelectedText = selectedText
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
        updateAISelection(explicitText: currentWebSelectedText)

        if currentWebSelectedText.isEmpty {
            hideSelectionToolbar()
        } else {
            showSelectionToolbarForWebSelection(rect: currentWebSelectionRect, text: currentWebSelectedText)
        }
    }

    func setWebSelectionFromVisibleText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        setWebSelection(text: trimmed, context: trimmed, occurrenceIndex: nil, rect: nil)
        aiPanel.setSelectedText(currentWebSelectedText)
    }

    private func updateAISelection(explicitText: String) {
        let selectedText = ReaderAIContextResolver(
            explicitSelection: explicitText,
            readAloudSelection: currentReadAloudSelectionTextForAI()
        ).preferredSelectionText
        aiPanel.setSelectedText(selectedText)
    }

    private func clearWebSelectionState() {
        currentWebSelectedText = ""
        currentWebSelectionContext = ""
        currentWebSelectionOccurrenceIndex = nil
        currentWebSelectionRect = nil
    }

    private func clearReaderDocumentSelection() {
        if currentDocumentKind == .pdf {
            pdfView.clearSelection()
        } else {
            clearWebSearchSelection()
        }
    }

    private func setWebSelection(text: String, context: String, occurrenceIndex: Int?, rect: NSRect?) {
        currentWebSelectedText = text.count > 1 ? text : ""
        currentWebSelectionContext = currentWebSelectedText.isEmpty ? "" : context
        currentWebSelectionOccurrenceIndex = currentWebSelectedText.isEmpty ? nil : occurrenceIndex
        currentWebSelectionRect = currentWebSelectedText.isEmpty ? nil : rect
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
