import Foundation

enum ReaderShellPresentationStateTests {
    static func testLoadingAndSearchTransitions() throws {
        var state = ReaderShellPresentationState()
        state.beginDocumentLoading()
        try expectEqual(state.isDocumentLoading, true, "loading becomes visible at the start of a document load")
        state.showSearch()
        state.setSearchQuery("reader")
        try expectEqual(state.isSearchVisible, true, "search visibility is owned by shell presentation state")
        try expectEqual(state.searchQuery, "reader", "search query is a named presentation value")
        state.hideSearch()
        state.finishDocumentLoading()
        try expectEqual(state.isSearchVisible, false, "closing search updates the model")
        try expectEqual(state.isDocumentLoading, false, "finishing a document load updates the model")
        try expectEqual(state.projection.loadingOverlayHidden, true, "a finished load hides its native overlay")
        try expectEqual(state.projection.searchOverlayHidden, true, "a hidden search state hides its native overlay")
    }

    static func testProjectionAndDocumentResetStayIndependent() throws {
        var state = ReaderShellPresentationState()
        state.setSearchQuery("keep me until the document actually changes")
        state.beginDocumentLoading()
        try expectEqual(state.searchQuery, "keep me until the document actually changes", "loading does not overwrite search state")
        try expectEqual(state.projection.loadingOverlayHidden, false, "loading projects to a visible overlay")
        try expectEqual(state.projection.searchOverlayClearance, 64, "hidden search uses compact clearance")
        state.showSearch()
        try expectEqual(state.projection.searchOverlayHidden, false, "visible search projects to a visible overlay")
        try expectEqual(state.projection.searchOverlayClearance, 150, "visible search reserves expanded clearance")
        state.resetForDocumentChange()
        try expectEqual(state.searchQuery, "", "document changes explicitly reset search state")
        try expectEqual(state.isSearchVisible, false, "document changes explicitly hide search")
    }

    static func testPanelStateIsIndependentFromAIData() throws {
        var state = ReaderShellPresentationState()
        state.isAIPanelCollapsed = false
        state.preferredAIWidth = 480
        try expectEqual(state.isAIPanelCollapsed, false, "panel expansion is shell presentation state")
        try expectEqual(state.preferredAIWidth, 480, "panel width is shell presentation state")
    }
}
