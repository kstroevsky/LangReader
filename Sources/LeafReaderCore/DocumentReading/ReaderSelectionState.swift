import Foundation

/// What the reader currently has selected, for whichever document kind is open.
///
/// Split out of `DocumentSession`, which had grown to hold four unrelated
/// concerns — document identity, this selection, web presentation, and reading
/// position. Selection is the one the rest of the app reads constantly: the AI
/// panel asks for it to answer about, vocabulary saving turns it into a word,
/// and note creation turns it into a quote.
///
/// Platform-neutral on purpose, and now *semantic* only: the toolbar's anchor
/// rectangle moved to `ReaderSelectionPresentation`, so consumers that want to
/// know what the reader picked no longer carry presentation coordinates that go stale
/// as soon as the view scrolls.
package struct ReaderSelectionState: Equatable {
    /// Swift synthesises a memberwise initialiser at `internal`, which stops at
    /// the module edge, so every core type the app constructs needs one spelled
    /// out. These are all "empty state" types, so an empty initialiser is the
    /// whole surface.
    package init() {}

    /// The PDF path's selected text, mirrored here because `PDFSelection`
    /// itself is not something the rest of the app should hold.
    package var pdfSelectedText = ""

    /// The web path keeps more: the selection's surrounding context and which
    /// occurrence it was, so a saved word can be found again in the page.
    package var webSelectedText = ""
    package var webSelectionContext = ""
    package var webSelectionOccurrenceIndex: Int?

    /// True when nothing is selected in either path.
    package var isEmpty: Bool {
        pdfSelectedText.isEmpty && webSelectedText.isEmpty
    }

    /// The selected text for whichever path has one, preferring the web path
    /// since a PDF selection is left stale when a web document is open.
    package func selectedText(for kind: ReaderDocumentKind) -> String {
        kind == .pdf ? pdfSelectedText : webSelectedText
    }

    package mutating func clear() {
        self = Self()
    }
}
