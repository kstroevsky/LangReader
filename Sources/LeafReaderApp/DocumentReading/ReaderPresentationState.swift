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
/// This type grows only when another presentation fact needs an authoritative owner
/// or currently has duplicate mutable owners. Native PDFKit/WebKit state is not
/// mirrored here merely to make the type look comprehensive. The PDF zoom
/// percentage is kept because the editable toolbar field used to be both its
/// display and data source; the PDF view remains the rendering adapter.
package struct ReaderPresentationState: Equatable {
    package init() {}

    /// The logical document title. Empty until a document (or the empty-state
    /// chrome) sets one.
    package private(set) var documentTitle: String = ""

    /// The PDF zoom percentage shown by the reader chrome. PDFKit still owns
    /// the scale factor; this typed value is the state that the editable field
    /// reflects and that commands update after applying a native scale.
    package private(set) var pdfZoomPercent: Int = 100

    package mutating func setDocumentTitle(_ title: String) {
        documentTitle = title
    }

    package mutating func setPDFZoomPercent(_ percent: Int) {
        pdfZoomPercent = min(max(percent, 10), 800)
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
