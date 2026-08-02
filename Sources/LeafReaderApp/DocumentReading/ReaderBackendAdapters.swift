import CoreGraphics
import PDFKit
import WebKit
import LeafReaderCore

/// The platform engines differ, but feature code shares these document-reader
/// commands. Two adapters make this a real seam: PDFKit and WebKit retain the
/// rendering implementation while the Reader Shell owns the shared intent.
enum ReaderContentBackendKind: Equatable {
    case pdf
    case web
}

enum ReaderZoomStep {
    case increment
    case decrement
}

@MainActor
protocol ReaderContentBackend: AnyObject {
    var kind: ReaderContentBackendKind { get }
    var zoomPercent: Int? { get }

    func clearSelection()
    @discardableResult func setZoomPercent(_ percent: Int) -> Int?
    @discardableResult func stepZoom(_ step: ReaderZoomStep) -> Int?
}

@MainActor
protocol ReaderPagedBackend: ReaderContentBackend {
    var currentPageIndex: Int? { get }
    var pageCount: Int { get }
    @discardableResult func go(toPage index: Int) -> Bool
}

@MainActor
final class PDFKitReaderAdapter: ReaderPagedBackend {
    private weak var view: PDFView?

    init(view: PDFView) {
        self.view = view
    }

    let kind: ReaderContentBackendKind = .pdf

    var currentPageIndex: Int? {
        guard let view, let document = view.document, let page = view.currentPage else { return nil }
        return document.index(for: page)
    }

    var pageCount: Int { view?.document?.pageCount ?? 0 }

    var zoomPercent: Int? {
        guard let view else { return nil }
        return Int(round(view.scaleFactor * 100))
    }

    func clearSelection() {
        view?.clearSelection()
    }

    @discardableResult
    func setZoomPercent(_ percent: Int) -> Int? {
        guard let view else { return nil }
        view.autoScales = false
        view.scaleFactor = ReaderFieldInput.clampedPDFScale(percent: Double(percent))
        return zoomPercent
    }

    @discardableResult
    func stepZoom(_ step: ReaderZoomStep) -> Int? {
        guard let view else { return nil }
        let multiplier: CGFloat = step == .increment ? 1.25 : 0.8
        view.autoScales = false
        view.scaleFactor = min(max(view.scaleFactor * multiplier, 0.1), 8)
        return zoomPercent
    }

    @discardableResult
    func go(toPage index: Int) -> Bool {
        guard let view,
              let page = view.document?.page(at: index) else {
            return false
        }
        view.go(to: page)
        return true
    }
}

@MainActor
final class WebKitReaderAdapter: ReaderContentBackend {
    private weak var view: WKWebView?
    private var appliedZoomPercent = 100

    init(view: WKWebView) {
        self.view = view
    }

    let kind: ReaderContentBackendKind = .web

    var zoomPercent: Int? { appliedZoomPercent }

    func clearSelection() {
        view?.evaluateJavaScript("window.leafReaderClearSelection && window.leafReaderClearSelection();")
    }

    @discardableResult
    func setZoomPercent(_ percent: Int) -> Int? {
        let clamped = ReaderFieldInput.clampedWebZoom(percent: percent)
        appliedZoomPercent = clamped
        guard let view else { return nil }
        view.pageZoom = 1
        view.evaluateJavaScript("""
        document.documentElement.style.setProperty('--reader-zoom', '\(Double(clamped) / 100)');
        """)
        return clamped
    }

    @discardableResult
    func stepZoom(_ step: ReaderZoomStep) -> Int? {
        let delta = step == .increment ? 10 : -10
        return setZoomPercent(appliedZoomPercent + delta)
    }
}
