import Foundation

enum DocumentSessionLogicTests {
    static func testLoadTicketsRejectSupersededAndUnloadedWork() throws {
        var session = DocumentSession()
        let firstGeneration = session.beginLoading()
        let secondGeneration = session.beginLoading()

        try expect(!session.acceptsLoad(generation: firstGeneration), "a newer document load should supersede the earlier load")
        try expect(session.acceptsLoad(generation: secondGeneration), "the current document load should be accepted")

        session.unload()
        try expect(!session.acceptsLoad(generation: secondGeneration), "unloading a document should invalidate outstanding load work")
    }

    static func testAdoptingDocumentResetsDocumentBoundState() throws {
        var session = DocumentSession()
        let generation = session.beginLoading()
        session.web.plainText = "old web content"
        session.selection.pdfSelectedText = "old PDF selection"
        session.selection.webSelectedText = "old web selection"
        session.selection.webSelectionContext = "old context"
        session.selection.webSelectionOccurrenceIndex = 3
        session.selectionPresentation.anchorRect = .init(x: 1, y: 2, width: 3, height: 4)
        session.web.pendingProgressRestore = ReaderWebPresentation.PendingProgressRestore(
            generation: generation, progress: 0.8, zoomPercent: 150
        )
        session.web.zoomPercent = 150
        session.web.scrollProgress = 0.8
        session.position.lastPageIndex = 8

        let url = URL(fileURLWithPath: "/books/new.epub")
        session.adopt(url: url, kind: .epub, documentID: "new-book")

        try expectEqual(session.currentFileURL, url, "adopted session should own the new document URL")
        try expectEqual(session.currentFileMD5, "new-book", "adopted session should own the new document identity")
        try expectEqual(session.currentDocumentKind, .epub, "adopted session should own the new document kind")
        try expectEqual(session.web.plainText, "", "adopting a document should clear previous web content")
        try expectEqual(session.selection.pdfSelectedText, "", "adopting a document should clear previous PDF selection")
        try expectEqual(session.selection.webSelectedText, "", "adopting a document should clear previous web selection")
        try expectEqual(session.selection.webSelectionContext, "", "adopting a document should clear previous web context")
        try expect(session.selection.webSelectionOccurrenceIndex == nil, "adopting a document should clear previous selection occurrence")
        try expect(session.selectionPresentation.anchorRect == nil, "adopting a document should clear previous selection bounds")
        try expect(session.web.pendingProgressRestore == nil, "adopting a document should clear a pending web restoration")
        try expectEqual(session.web.zoomPercent, 100, "adopting a document should reset web zoom")
        try expectEqual(session.web.scrollProgress, 0, "adopting a document should reset web progress")
        try expect(session.position.lastPageIndex == nil, "adopting a document should clear the previous page index")
        try expect(session.acceptsLoad(generation: generation), "adopting content should preserve the active load ticket")
    }
    static func testSelectionIsClearedWhenTheDocumentChanges() throws {
        var session = DocumentSession()
        session.selection.pdfSelectedText = "a pdf phrase"
        session.selection.webSelectedText = "a web phrase"
        session.selection.webSelectionContext = "surrounding context"
        session.selection.webSelectionOccurrenceIndex = 3
        session.selectionPresentation.anchorRect = CGRect(x: 1, y: 2, width: 3, height: 4)

        session.adopt(url: URL(fileURLWithPath: "/tmp/next.pdf"), kind: .pdf, documentID: "id-2")

        try expect(session.selection.isEmpty, "opening another document must not leave the old selection behind")
        try expect(session.selectionPresentation.anchorRect == nil, "the toolbar anchor belongs to the old page")
        try expect(session.selection.webSelectionOccurrenceIndex == nil, "the occurrence index belongs to the old page")
    }

    static func testSelectionIsClearedOnUnload() throws {
        var session = DocumentSession()
        session.selection.pdfSelectedText = "still selected"

        session.unload()

        try expect(session.selection.isEmpty, "unloading must clear the selection")
    }

    /// A toolbar needs a rectangle with area to sit against. The web path signals
    /// "no usable selection" with a zero-sized rect, so this rule decides whether
    /// the toolbar is shown at all.
    static func testAToolbarAnchorNeedsArea() throws {
        var presentation = ReaderSelectionPresentation()
        try expect(!presentation.canAnchorToolbar, "no rectangle means nothing to anchor to")

        presentation.anchorRect = CGRect(x: 10, y: 10, width: 0, height: 12)
        try expect(!presentation.canAnchorToolbar, "a zero-width anchor is not usable")

        presentation.anchorRect = CGRect(x: 10, y: 10, width: 40, height: 0)
        try expect(!presentation.canAnchorToolbar, "a zero-height anchor is not usable")

        presentation.anchorRect = CGRect(x: 10, y: 10, width: 40, height: 12)
        try expect(presentation.canAnchorToolbar, "a rectangle with area can host the toolbar")
    }

    /// The anchor is presentation geometry and must not outlive the document it
    /// was measured in — window coordinates from the previous page would place
    /// the toolbar over unrelated content.
    static func testTheToolbarAnchorIsClearedOnUnload() throws {
        var session = DocumentSession()
        session.selectionPresentation.anchorRect = CGRect(x: 1, y: 2, width: 3, height: 4)
        session.selectionPresentation.preferredEdge = .below

        session.unload()

        try expect(session.selectionPresentation.anchorRect == nil, "unloading must drop the stale anchor")
        try expect(session.selectionPresentation.preferredEdge == .above, "the edge returns to its default")
    }

    static func testSelectedTextFollowsTheDocumentKind() throws {
        var selection = ReaderSelectionState()
        selection.pdfSelectedText = "from the pdf"
        selection.webSelectedText = "from the page"

        try expectEqual(selection.selectedText(for: .pdf), "from the pdf", "a PDF document reads the PDF selection")
        try expectEqual(selection.selectedText(for: .epub), "from the page", "a web-backed document reads the web selection")
    }

    static func testPlainTextGenerationSurvivesADocumentChange() throws {
        var session = DocumentSession()
        let firstGeneration = session.web.invalidatePlainText()
        try expect(session.web.acceptsPlainText(generation: firstGeneration), "the live generation should be accepted")

        session.adopt(url: URL(fileURLWithPath: "/tmp/other.epub"), kind: .epub, documentID: "id-2")

        // The counter must move past the old value rather than restart, or text
        // extraction still running for the previous document would be accepted
        // and land in the new one.
        try expect(
            !session.web.acceptsPlainText(generation: firstGeneration),
            "extraction from the previous document must be rejected after a change"
        )
        try expect(session.web.plainText.isEmpty, "the new document starts with no extracted text")
    }

    static func testPendingProgressRestoreIsScopedToItsLoad() throws {
        var session = DocumentSession()
        let generation = session.beginLoading()
        session.web.pendingProgressRestore = ReaderWebPresentation.PendingProgressRestore(
            generation: generation, progress: 0.5, zoomPercent: nil
        )

        try expect(session.web.acceptsProgressRestore(loadGeneration: generation), "its own load should be accepted")
        try expect(
            !session.web.acceptsProgressRestore(loadGeneration: generation + 1),
            "a restore saved for an earlier load must not scroll a later one"
        )
    }

    static func testReadingPositionIsClearedWithTheDocument() throws {
        var session = DocumentSession()
        session.position.lastPageIndex = 12
        session.position.lastPersonalVocabularyPDFPageIndex = 12
        session.position.lastPersonalVocabularyWebProgressBucket = 4

        session.adopt(url: URL(fileURLWithPath: "/tmp/next.pdf"), kind: .pdf, documentID: "id-3")

        try expectEqual(session.position, ReaderReadingPosition(), "position belongs to the document that was open")
    }

}
