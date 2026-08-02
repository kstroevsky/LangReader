import CoreGraphics
import PDFKit
import WebKit
import LeafReaderCore

/// A small seam for native reader operations that are shared by feature code.
/// The interface describes commands and snapshots, not the rendering views.
@MainActor
protocol ReaderSelectionProviding: AnyObject {
    func clearSelection()
}

@MainActor
protocol ReaderZoomProviding: AnyObject {
    /// WebKit's reader zoom is CSS-driven, so it has no native scale snapshot.
    var nativeZoomPercent: Int? { get }
    func setScaleFactor(_ scaleFactor: CGFloat)
    func applyZoomPercent(_ percent: Int)
}

@MainActor
protocol ReaderNavigationProviding: AnyObject {
    var currentPageIndex: Int? { get }
    var pageCount: Int { get }
}

@MainActor
final class PDFKitReaderAdapter: ReaderSelectionProviding, ReaderZoomProviding, ReaderNavigationProviding {
    private weak var view: PDFView?

    init(view: PDFView) {
        self.view = view
    }

    var currentPageIndex: Int? {
        guard let view, let document = view.document, let page = view.currentPage else { return nil }
        return document.index(for: page)
    }

    var pageCount: Int { view?.document?.pageCount ?? 0 }

    var nativeZoomPercent: Int? {
        guard let view else { return nil }
        return Int(round(view.scaleFactor * 100))
    }

    func clearSelection() {
        view?.clearSelection()
    }

    func setScaleFactor(_ scaleFactor: CGFloat) {
        guard let view else { return }
        view.autoScales = false
        view.scaleFactor = scaleFactor
    }

    func applyZoomPercent(_ percent: Int) {
        setScaleFactor(ReaderFieldInput.clampedPDFScale(percent: Double(percent)))
    }
}

@MainActor
final class WebKitReaderAdapter: ReaderSelectionProviding, ReaderZoomProviding {
    private weak var view: WKWebView?

    init(view: WKWebView) {
        self.view = view
    }

    var nativeZoomPercent: Int? { nil }

    func clearSelection() {
        view?.evaluateJavaScript("window.leafReaderClearSelection && window.leafReaderClearSelection();")
    }

    func setScaleFactor(_ scaleFactor: CGFloat) {
        applyZoomPercent(Int(round(scaleFactor * 100)))
    }

    func applyZoomPercent(_ percent: Int) {
        guard let view else { return }
        view.pageZoom = 1
        view.evaluateJavaScript("""
        document.documentElement.style.setProperty('--reader-zoom', '\(Double(percent) / 100)');
        """)
    }
}
