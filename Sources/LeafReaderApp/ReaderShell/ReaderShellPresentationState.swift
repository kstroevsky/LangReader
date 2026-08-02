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

    mutating func beginDocumentLoading() {
        isDocumentLoading = true
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

    /// A document change is the only intentional point at which a search is
    /// discarded. Starting a loading indicator must not silently change it.
    mutating func resetForDocumentChange() {
        isSearchVisible = false
        searchQuery = ""
    }

    var projection: ReaderShellProjection {
        ReaderShellProjection(
            loadingOverlayHidden: !isDocumentLoading,
            searchOverlayHidden: !isSearchVisible,
            searchOverlayClearance: isSearchVisible ? 150 : 64
        )
    }
}

/// The complete AppKit projection of Reader Shell presentation state. Keeping
/// the inversion here means native views cannot become a second source of
/// truth for visibility or layout decisions.
struct ReaderShellProjection: Equatable {
    let loadingOverlayHidden: Bool
    let searchOverlayHidden: Bool
    let searchOverlayClearance: CGFloat
}
