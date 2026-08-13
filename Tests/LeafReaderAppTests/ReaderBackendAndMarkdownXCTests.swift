import Cocoa
import XCTest
@testable import LeafReaderApp

@MainActor
final class ReaderBackendAndMarkdownXCTests: XCTestCase {
    func testFeatureCodeCanUsePagedBackendWithoutKnowingItsRenderer() {
        let backend = FakePagedReaderBackend()
        let content: any ReaderContentBackend = backend
        let paged: any ReaderPagedBackend = backend

        XCTAssertEqual(content.kind, .pdf)
        XCTAssertEqual(content.setZoomPercent(1000), 800)
        XCTAssertEqual(content.stepZoom(.decrement), 790)
        content.clearSelection()
        XCTAssertTrue(backend.didClearSelection)

        XCTAssertEqual(paged.pageCount, 3)
        XCTAssertTrue(paged.go(toPage: 2))
        XCTAssertEqual(paged.currentPageIndex, 2)
        XCTAssertTrue(paged.scrollToTop(ofPage: 1))
        XCTAssertEqual(backend.lastTopPageIndex, 1)
        let anchor = ReaderPagedViewportAnchor(pageIndex: 1, point: CGPoint(x: 12, y: 34))
        XCTAssertTrue(paged.restoreViewportAnchor(anchor))
        XCTAssertEqual(backend.restoredAnchor, anchor)
        XCTAssertFalse(paged.go(toPage: 3))
        content.focus()
        XCTAssertTrue(backend.didFocus)
    }

    func testTransientAIPlaceholderNeverSerializesToMarkdown() {
        let attributed = NSMutableAttributedString(string: "Before\n")
        attributed.append(NSAttributedString(
            string: "Generating answer",
            attributes: [.readingNoteTransientAIPlaceholder: true]
        ))
        attributed.append(NSAttributedString(string: "\nAfter"))

        let markdown = ReadingNoteMarkdownSerializer.markdown(from: attributed)
        XCTAssertEqual(markdown, "Before\n\nAfter\n")
        XCTAssertFalse(markdown.localizedCaseInsensitiveContains("generating"))
    }
}

@MainActor
private final class FakePagedReaderBackend: ReaderPagedBackend {
    let kind: ReaderContentBackendKind = .pdf
    private(set) var zoomPercent: Int? = 100
    private(set) var didClearSelection = false
    private(set) var didFocus = false
    private(set) var currentPageIndex: Int? = 0
    private(set) var lastTopPageIndex: Int?
    private(set) var restoredAnchor: ReaderPagedViewportAnchor?
    let pageCount = 3
    var viewportAnchor: ReaderPagedViewportAnchor? {
        currentPageIndex.map { ReaderPagedViewportAnchor(pageIndex: $0, point: .zero) }
    }

    func focus() {
        didFocus = true
    }

    func clearSelection() {
        didClearSelection = true
    }

    func setZoomPercent(_ percent: Int) -> Int? {
        zoomPercent = min(max(percent, 10), 800)
        return zoomPercent
    }

    func stepZoom(_ step: ReaderZoomStep) -> Int? {
        let delta = step == .increment ? 10 : -10
        return setZoomPercent((zoomPercent ?? 100) + delta)
    }

    func go(toPage index: Int) -> Bool {
        guard (0..<pageCount).contains(index) else { return false }
        currentPageIndex = index
        return true
    }

    func scrollToTop(ofPage index: Int) -> Bool {
        guard (0..<pageCount).contains(index) else { return false }
        lastTopPageIndex = index
        return true
    }

    func restoreViewportAnchor(_ anchor: ReaderPagedViewportAnchor) -> Bool {
        guard (0..<pageCount).contains(anchor.pageIndex) else { return false }
        restoredAnchor = anchor
        return true
    }
}
