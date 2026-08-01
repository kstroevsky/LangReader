import Foundation
import LeafReaderCore

/// The reader's authoritative presentation title — extracted out of
/// `titleLabel.stringValue` so read-aloud progress text can no longer be read
/// back as the document title.
enum ReaderPresentationStateTests {
    static func testDefaultTitleIsEmpty() throws {
        let state = ReaderPresentationState()
        try expectEqual(state.documentTitle, "", "a fresh presentation has no title")
    }

    static func testSetTitleIsAuthoritative() throws {
        var state = ReaderPresentationState()
        state.setDocumentTitle("Effi Briest")
        try expectEqual(state.documentTitle, "Effi Briest", "the model holds the title it was given")
    }

    static func testClearResetsTitle() throws {
        var state = ReaderPresentationState()
        state.setDocumentTitle("Effi Briest")
        state.clear()
        try expectEqual(state.documentTitle, "", "clearing returns to the empty title for the next document")
    }

    static func testTitleForURLDropsExtension() throws {
        let url = URL(fileURLWithPath: "/books/Der Vorleser.pdf")
        try expectEqual(ReaderPresentationState.documentTitle(for: url), "Der Vorleser",
                        "the document title is the file name without its extension")
    }

    static func testTitleForURLIsStableAcrossPaths() throws {
        // The PDF and web load paths must derive the same title for the same
        // file, which is the whole reason the derivation lives in one place.
        let a = URL(fileURLWithPath: "/a/Wörterbuch.epub")
        let b = URL(fileURLWithPath: "/deeply/nested/other/Wörterbuch.epub")
        try expectEqual(ReaderPresentationState.documentTitle(for: a),
                        ReaderPresentationState.documentTitle(for: b),
                        "the same file name yields the same title regardless of directory")
    }
}
