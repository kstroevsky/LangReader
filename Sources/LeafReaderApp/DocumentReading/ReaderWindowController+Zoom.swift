import Foundation
import LeafReaderCore

extension ReaderWindowController {
    @objc func zoomIn() {
        let startedAt = ProcessInfo.processInfo.systemUptime
        defer { recordZoomPerformance(startedAt: startedAt) }
        markReaderInteraction()
        guard let percent = activeReaderBackend?.stepZoom(.increment) else { return }
        syncZoomPercentFromBackend(percent)
        updateZoomLabel()
        saveSession()
    }

    @objc func zoomOut() {
        let startedAt = ProcessInfo.processInfo.systemUptime
        defer { recordZoomPerformance(startedAt: startedAt) }
        markReaderInteraction()
        guard let percent = activeReaderBackend?.stepZoom(.decrement) else { return }
        syncZoomPercentFromBackend(percent)
        updateZoomLabel()
        saveSession()
    }

    @objc func applyZoomFromField() {
        let startedAt = ProcessInfo.processInfo.systemUptime
        defer { recordZoomPerformance(startedAt: startedAt) }
        markReaderInteraction()
        guard let percent = ReaderFieldInput.zoomPercent(from: zoomField.stringValue) else {
            updateZoomLabel()
            return
        }
        guard let applied = activeReaderBackend?.setZoomPercent(Int(percent)) else { return }
        syncZoomPercentFromBackend(applied)
        updateZoomLabel()
        saveSession()
        window?.makeFirstResponder(currentDocumentKind == .pdf ? pdfView : webView)
    }

    func setWebZoom(_ percent: Int) {
        let startedAt = ProcessInfo.processInfo.systemUptime
        defer { recordZoomPerformance(startedAt: startedAt) }
        guard let applied = activeReaderBackend?.setZoomPercent(percent) else { return }
        documentSession.web.zoomPercent = applied
        updateZoomLabel()
        saveSession()
        window?.makeFirstResponder(webView)
    }

    func applyWebZoomToPage() {
        _ = activeReaderBackend?.setZoomPercent(documentSession.web.zoomPercent)
    }

    private func syncZoomPercentFromBackend(_ percent: Int) {
        if currentDocumentKind == .pdf {
            setPDFZoomPercent(percent)
        } else {
            documentSession.web.zoomPercent = percent
        }
    }

    private func recordZoomPerformance(startedAt: TimeInterval) {
        let event: PerformanceEvent = currentDocumentKind == .pdf
            ? .pdfZoomHighlightUpdate
            : .webFontHighlightUpdate
        ReaderPerformance.record(
            event,
            milliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        )
        ReaderPerformance.recordMainThreadWork(startedAt: startedAt)
    }
}
