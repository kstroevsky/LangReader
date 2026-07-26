import Foundation

/// Which side of the selection the floating toolbar prefers to sit on.
///
/// Lifted out of `ReaderWindowController`, where it was a nested enum and so
/// could only be named through an AppKit class, even though the choice itself is
/// pure geometry.
enum SelectionToolbarEdge {
    case above
    case below
}

/// Where the selection toolbar should be drawn — presentation geometry, kept
/// apart from *what* is selected.
///
/// The anchor rectangle used to live in `ReaderSelectionState` beside the
/// selected text and its occurrence index. Those answer "what did the reader
/// pick?", which vocabulary saving, note creation and the AI panel all consume;
/// this answers "where do we float a toolbar?", which only the toolbar cares
/// about. Keeping them in one struct meant every consumer of the selection also
/// carried window coordinates that go stale the moment the view scrolls.
struct ReaderSelectionPresentation: Equatable {
    /// The rectangle to anchor the toolbar to, in window coordinates. Nil when
    /// there is nothing to anchor to.
    ///
    /// Only the web path stores this: it arrives pushed from JavaScript on each
    /// selection change. The PDF path asks PDFKit for the geometry when it needs
    /// it, which is the pattern to prefer — a stored rectangle is only as fresh
    /// as the last event that set it.
    var anchorRect: CGRect?

    /// Which side of the anchor to prefer. The web path asks for `.below`
    /// because its anchor is the selection's own rectangle; PDF defaults to
    /// `.above`.
    var preferredEdge: SelectionToolbarEdge = .above

    /// A toolbar can only be placed against a rectangle with area. A zero-sized
    /// anchor is how the web path says "there is no usable selection", so this
    /// keeps that rule in one place rather than repeating the width/height check
    /// at each call site.
    var canAnchorToolbar: Bool {
        guard let anchorRect else { return false }
        return anchorRect.width > 0 && anchorRect.height > 0
    }

    mutating func clear() {
        self = Self()
    }
}
