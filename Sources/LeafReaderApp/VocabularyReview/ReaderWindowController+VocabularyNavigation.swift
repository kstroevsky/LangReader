import Cocoa
import PDFKit

extension ReaderWindowController {
    func jumpToStoredLinkedWord(linkID: String) {
        if linkID.hasPrefix("document-source:") {
            let rawIndex = String(linkID.dropFirst("document-source:".count))
            if let index = Int(rawIndex) {
                jumpToDocumentSource(index: index)
            }
            return
        }
        if linkID.hasPrefix("pdf-page:") {
            let rawPage = String(linkID.dropFirst("pdf-page:".count))
            if let pageIndex = Int(rawPage) {
                jumpToPDFPage(index: pageIndex, skipIfCurrentPage: false)
            }
            return
        }
        if storedWebWordRecords.contains(where: { $0.id == linkID }) {
            jumpToStoredWebWord(linkID: linkID)
            return
        }
        jumpToStoredPDFWord(linkID: linkID)
    }

    func jumpToStoredPDFWord(linkID: String) {
        guard let record = storedWordRecords.first(where: { $0.id == linkID }),
              let page = pdfView.document?.page(at: record.pageIndex) else {
            return
        }
        setAIPanelCollapsed(false, animated: true)
        let bounds = displayBounds(for: record, page: page)
        let destination = PDFDestination(
            page: page,
            at: NSPoint(x: bounds.minX, y: bounds.maxY + 80)
        )
        pdfView.go(to: destination)
        lastPageIndex = record.pageIndex
        updatePageLabel()
        saveSession()
    }

    func jumpToStoredWebWord(linkID: String) {
        guard let record = storedWebWordRecords.first(where: { $0.id == linkID }) else { return }
        setAIPanelCollapsed(false, animated: true)
        webView.evaluateJavaScript("window.leafReaderScrollToWord(\(jsStringLiteral(linkID)), \(record.scrollProgress));")
    }

    func selectStoredLinkedWord(linkID: String) {
        let focused: (word: String, answer: String)?
        if let record = storedWordRecords.first(where: { $0.id == linkID }) {
            focused = (record.word, record.answer)
        } else if let record = storedWebWordRecords.first(where: { $0.id == linkID }) {
            focused = (record.word, record.answer)
        } else {
            focused = nil
        }
        guard let focused else { return }
        setAIPanelCollapsed(false, animated: true)
        // Clicking a saved word shows the same focused card as defining it, not a
        // scroll into a list of every word (which no longer exists).
        aiPanel.showFocusedWord(
            word: focused.word,
            answer: focused.answer.trimmingCharacters(in: .whitespacesAndNewlines),
            linkID: linkID
        )
    }

    @discardableResult
    func ensureLinkedWordBubbleLoaded(linkID: String) -> Bool {
        guard !aiPanel.hasLinkedBubble(id: linkID) else { return true }
        if let record = storedWordRecords.first(where: { $0.id == linkID }) {
            let answer = record.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else { return false }
            aiPanel.appendLinkedWordBubbleIfNeeded(AIChatPanel.LinkedWordBubble(
                id: record.id,
                word: record.word,
                question: record.question,
                answer: answer
            ))
            return true
        }
        if let record = storedWebWordRecords.first(where: { $0.id == linkID }) {
            let answer = record.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else { return false }
            aiPanel.appendLinkedWordBubbleIfNeeded(AIChatPanel.LinkedWordBubble(
                id: record.id,
                word: record.word,
                question: record.question,
                answer: answer
            ))
            return true
        }
        return false
    }
}
