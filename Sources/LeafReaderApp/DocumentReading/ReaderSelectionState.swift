import Foundation

/// What the reader currently has selected, for whichever document kind is open.
///
/// Split out of `DocumentSession`, which had grown to hold four unrelated
/// concerns — document identity, this selection, web presentation, and reading
/// position. Selection is the one the rest of the app reads constantly: the AI
/// panel asks for it to answer about, vocabulary saving turns it into a word,
/// and note creation turns it into a quote.
///
/// Platform-neutral on purpose. It uses `CGRect` rather than `NSRect` (the same
/// type on macOS, but only one of the two spellings exists everywhere), so this
/// compiles unchanged on a platform without AppKit.
struct ReaderSelectionState: Equatable {
    /// The PDF path's selected text, mirrored here because `PDFSelection`
    /// itself is not something the rest of the app should hold.
    var pdfSelectedText = ""

    /// The web path keeps more: the selection's surrounding context and which
    /// occurrence it was, so a saved word can be found again in the page.
    var webSelectedText = ""
    var webSelectionContext = ""
    var webSelectionOccurrenceIndex: Int?
    /// Where to anchor the selection toolbar, in window coordinates.
    var webSelectionRect: CGRect?

    /// True when nothing is selected in either path.
    var isEmpty: Bool {
        pdfSelectedText.isEmpty && webSelectedText.isEmpty
    }

    /// The selected text for whichever path has one, preferring the web path
    /// since a PDF selection is left stale when a web document is open.
    func selectedText(for kind: ReaderDocumentKind) -> String {
        kind == .pdf ? pdfSelectedText : webSelectedText
    }

    mutating func clear() {
        self = Self()
    }
}
