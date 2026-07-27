import Foundation
import LeafReaderCore

extension ReaderWindowController {
    @objc func zoomIn() {
        markReaderInteraction()
        guard currentDocumentKind == .pdf else {
            setWebZoom(webZoomPercent + 10)
            return
        }
        pdfView.autoScales = false
        pdfView.scaleFactor = min(pdfView.scaleFactor * 1.25, 8)
        updateZoomLabel()
        saveSession()
    }

    @objc func zoomOut() {
        markReaderInteraction()
        guard currentDocumentKind == .pdf else {
            setWebZoom(webZoomPercent - 10)
            return
        }
        pdfView.autoScales = false
        pdfView.scaleFactor = max(pdfView.scaleFactor * 0.8, 0.1)
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
        pdfView.autoScales = false
        pdfView.scaleFactor = ReaderFieldInput.clampedPDFScale(percent: percent)
        updateZoomLabel()
        saveSession()
        window?.makeFirstResponder(currentDocumentKind == .pdf ? pdfView : webView)
    }

    func setWebZoom(_ percent: Int) {
        webZoomPercent = ReaderFieldInput.clampedWebZoom(percent: percent)
        zoomField.stringValue = "\(webZoomPercent)%"
        applyWebZoomToPage()
        saveSession()
        window?.makeFirstResponder(webView)
    }

    func applyWebZoomToPage() {
        guard webView != nil else { return }
        webView.pageZoom = 1
        webView.evaluateJavaScript("""
        document.documentElement.style.setProperty('--reader-zoom', '\(Double(webZoomPercent) / 100)');
        """)
    }
}
