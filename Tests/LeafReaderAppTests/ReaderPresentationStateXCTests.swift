import XCTest
@testable import LeafReaderApp

final class ReaderPresentationStateXCTests: XCTestCase {
    func testDefaultTitleIsEmpty() {
        XCTAssertEqual(ReaderPresentationState().documentTitle, "")
    }

    func testSetTitleIsAuthoritative() {
        var state = ReaderPresentationState()
        state.setDocumentTitle("Effi Briest")
        XCTAssertEqual(state.documentTitle, "Effi Briest")
    }

    func testPDFZoomDefaultsTo100Percent() {
        XCTAssertEqual(ReaderPresentationState().pdfZoomPercent, 100)
    }

    func testPDFZoomIsClamped() {
        var state = ReaderPresentationState()
        state.setPDFZoomPercent(245)
        XCTAssertEqual(state.pdfZoomPercent, 245)
        state.setPDFZoomPercent(999)
        XCTAssertEqual(state.pdfZoomPercent, 800)
        state.setPDFZoomPercent(1)
        XCTAssertEqual(state.pdfZoomPercent, 10)
    }

    func testClearResetsTitleAndZoom() {
        var state = ReaderPresentationState()
        state.setDocumentTitle("Effi Briest")
        state.setPDFZoomPercent(245)
        state.clear()
        XCTAssertEqual(state.documentTitle, "")
        XCTAssertEqual(state.pdfZoomPercent, 100)
    }

    func testTitleForURLDropsExtension() {
        let url = URL(fileURLWithPath: "/books/Der Vorleser.pdf")
        XCTAssertEqual(ReaderPresentationState.documentTitle(for: url), "Der Vorleser")
    }

    func testTitleForURLIsStableAcrossPaths() {
        let a = URL(fileURLWithPath: "/a/Wörterbuch.epub")
        let b = URL(fileURLWithPath: "/deeply/nested/other/Wörterbuch.epub")
        XCTAssertEqual(
            ReaderPresentationState.documentTitle(for: a),
            ReaderPresentationState.documentTitle(for: b)
        )
    }
}
