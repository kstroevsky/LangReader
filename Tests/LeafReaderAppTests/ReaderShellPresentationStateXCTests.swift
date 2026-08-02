import XCTest
@testable import LeafReaderApp

@MainActor
final class ReaderShellPresentationStateXCTests: XCTestCase {
    func testProjectionMakesOverlayVisibilityAFunctionOfState() {
        var state = ReaderShellPresentationState()
        XCTAssertTrue(state.projection.loadingOverlayHidden)
        XCTAssertTrue(state.projection.searchOverlayHidden)

        state.beginDocumentLoading()
        state.showSearch()
        state.setSearchQuery("needle")
        XCTAssertFalse(state.projection.loadingOverlayHidden)
        XCTAssertFalse(state.projection.searchOverlayHidden)
        XCTAssertEqual(state.projection.searchOverlayClearance, 150)

        state.finishDocumentLoading()
        state.hideSearch()
        XCTAssertTrue(state.projection.loadingOverlayHidden)
        XCTAssertTrue(state.projection.searchOverlayHidden)
        XCTAssertEqual(state.projection.searchOverlayClearance, 64)
    }

    func testDocumentChangeExplicitlyResetsSearchWithoutMutatingLoadTransition() {
        var state = ReaderShellPresentationState()
        state.showSearch()
        state.setSearchQuery("keep until document reset")
        state.beginDocumentLoading()
        XCTAssertEqual(state.searchQuery, "keep until document reset")

        state.resetForDocumentChange()
        XCTAssertFalse(state.isSearchVisible)
        XCTAssertEqual(state.searchQuery, "")
    }
}
