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
    }

    static func testPanelStateIsIndependentFromAIData() throws {
        var state = ReaderShellPresentationState()
        state.isAIPanelCollapsed = false
        state.preferredAIWidth = 480
        try expectEqual(state.isAIPanelCollapsed, false, "panel expansion is shell presentation state")
        try expectEqual(state.preferredAIWidth, 480, "panel width is shell presentation state")
    }
}
