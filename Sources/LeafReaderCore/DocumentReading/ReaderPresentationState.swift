import Foundation

/// The reader's authoritative *presentation* facts — what is currently being
/// shown — kept apart from document identity (`DocumentSession`) and from the
/// selection.
///
/// This exists because the reader was using AppKit controls as application data:
/// the document title lived only in `titleLabel.stringValue`, which AI context,
/// embedding, and read-aloud all read back. That is fragile in a way that bit:
/// read-aloud temporarily overwrites the title label with progress text, so a
/// context built during playback captured the progress line *as the title*.
/// With the title owned here, the label is free to show whatever it likes while
/// consumers read the real value.
///
/// This type grows only when another presentation fact needs a portable owner
/// or currently has duplicate mutable owners. Native PDFKit/WebKit state is not
/// mirrored here merely to make the type look comprehensive.
package struct ReaderPresentationState: Equatable {
    package init() {}

    /// The logical document title. Empty until a document (or the empty-state
    /// chrome) sets one.
    package private(set) var documentTitle: String = ""

    package mutating func setDocumentTitle(_ title: String) {
        documentTitle = title
    }

    package mutating func clear() {
        self = Self()
    }

    /// The title a document at `url` should show. Both the PDF and the web load
    /// paths derive it, and derived it two textually-identical but separately
    /// maintained ways before this; one definition keeps them from drifting.
    package static func documentTitle(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }
}
