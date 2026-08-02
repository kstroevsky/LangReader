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
        XCTAssertFalse(paged.go(toPage: 3))
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
    private(set) var currentPageIndex: Int? = 0
    let pageCount = 3

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
}
