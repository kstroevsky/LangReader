import Foundation
import LeafReaderCore

extension ReaderWindowController {
    @objc func zoomIn() {
        markReaderInteraction()
        guard let percent = activeReaderBackend?.stepZoom(.increment) else { return }
        syncZoomPercentFromBackend(percent)
        updateZoomLabel()
        saveSession()
    }

    @objc func zoomOut() {
        markReaderInteraction()
        guard let percent = activeReaderBackend?.stepZoom(.decrement) else { return }
        syncZoomPercentFromBackend(percent)
        updateZoomLabel()
        saveSession()
    }

    @objc func applyZoomFromField() {
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
}
