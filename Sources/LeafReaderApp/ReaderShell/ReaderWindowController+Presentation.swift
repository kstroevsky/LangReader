import Cocoa

extension ReaderWindowController {
    /// Mutate Reader Shell presentation state, then project it to AppKit in one
    /// place. SwiftUI chrome reads the same state through its focused models;
    /// AppKit remains only the imperative rendering edge.
    func mutateReaderPresentation(_ mutate: (inout ReaderShellPresentationState) -> Void) {
        mutate(&readerPresentation)
        renderReaderShellPresentation()
    }

    func renderReaderShellPresentation() {
        let projection = readerPresentation.projection
        loadingOverlay.isHidden = projection.loadingOverlayHidden
        if projection.loadingOverlayHidden {
            loadingIndicator.stopAnimation(nil)
        } else {
            loadingIndicator.startAnimation(nil)
        }

        searchOverlay.isHidden = projection.searchOverlayHidden
        searchOverlay.setQuery(readerPresentation.searchQuery)
    }
}
