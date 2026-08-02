import CoreGraphics

/// Presentation facts for the Reader Shell that used to be stored directly
/// on native controls or mixed into AI coordination. The AppKit views remain
/// adapters; this value is the authoritative owner for the chrome state that
/// other features need to inspect.
struct ReaderShellPresentationState: Equatable {
    var isDocumentLoading = false
    var isSearchVisible = false
    var searchQuery = ""
    var isAIPanelCollapsed = true
    var preferredAIWidth: CGFloat = 420
    var isFullScreen = false

    mutating func beginDocumentLoading(query: String = "") {
        isDocumentLoading = true
        searchQuery = query
    }

    mutating func finishDocumentLoading() {
        isDocumentLoading = false
    }

    mutating func showSearch() {
        isSearchVisible = true
    }

    mutating func hideSearch() {
        isSearchVisible = false
    }

    mutating func setSearchQuery(_ query: String) {
        searchQuery = query
    }
}
