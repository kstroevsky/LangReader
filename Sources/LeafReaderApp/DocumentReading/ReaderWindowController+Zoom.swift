import Foundation
import LeafReaderCore

extension ReaderWindowController {
    @objc func zoomIn() {
        markReaderInteraction()
        guard currentDocumentKind == .pdf else {
            setWebZoom(documentSession.web.zoomPercent + 10)
            return
        }
        pdfReaderAdapter.setScaleFactor(min(pdfView.scaleFactor * 1.25, 8))
        syncPDFZoomPercentFromNative()
        updateZoomLabel()
        saveSession()
    }

    @objc func zoomOut() {
        markReaderInteraction()
        guard currentDocumentKind == .pdf else {
            setWebZoom(documentSession.web.zoomPercent - 10)
            return
        }
        pdfReaderAdapter.setScaleFactor(max(pdfView.scaleFactor * 0.8, 0.1))
        syncPDFZoomPercentFromNative()
        updateZoomLabel()
        saveSession()
    }

    @objc func applyZoomFromField() {
        markReaderInteraction()
        guard currentDocumentKind == .pdf else {
            guard let percent = ReaderFieldInput.zoomPercent(from: zoomField.stringValue) else {
                updateZoomLabel()
                return
            }
            setWebZoom(Int(percent))
            return
        }
        guard let percent = ReaderFieldInput.zoomPercent(from: zoomField.stringValue) else {
            updateZoomLabel()
            return
        }
        pdfReaderAdapter.applyZoomPercent(Int(percent))
        syncPDFZoomPercentFromNative()
        updateZoomLabel()
        saveSession()
        window?.makeFirstResponder(currentDocumentKind == .pdf ? pdfView : webView)
    }

    func setWebZoom(_ percent: Int) {
        documentSession.web.zoomPercent = ReaderFieldInput.clampedWebZoom(percent: percent)
        updateZoomLabel()
        applyWebZoomToPage()
        saveSession()
        window?.makeFirstResponder(webView)
    }

    func applyWebZoomToPage() {
        webReaderAdapter.applyZoomPercent(documentSession.web.zoomPercent)
    }
}
