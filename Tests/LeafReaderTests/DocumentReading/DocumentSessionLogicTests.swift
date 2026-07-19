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
        session.currentWebPlainText = "old web content"
        session.currentPDFSelectedText = "old PDF selection"
        session.currentWebSelectedText = "old web selection"
        session.currentWebSelectionContext = "old context"
        session.currentWebSelectionOccurrenceIndex = 3
        session.currentWebSelectionRect = .init(x: 1, y: 2, width: 3, height: 4)
        session.pendingWebProgressRestore = (generation: generation, progress: 0.8, zoomPercent: 150)
        session.webZoomPercent = 150
        session.webScrollProgress = 0.8
        session.lastPageIndex = 8

        let url = URL(fileURLWithPath: "/books/new.epub")
        session.adopt(url: url, kind: .epub, documentID: "new-book")

        try expectEqual(session.currentFileURL, url, "adopted session should own the new document URL")
        try expectEqual(session.currentFileMD5, "new-book", "adopted session should own the new document identity")
        try expectEqual(session.currentDocumentKind, .epub, "adopted session should own the new document kind")
        try expectEqual(session.currentWebPlainText, "", "adopting a document should clear previous web content")
        try expectEqual(session.currentPDFSelectedText, "", "adopting a document should clear previous PDF selection")
        try expectEqual(session.currentWebSelectedText, "", "adopting a document should clear previous web selection")
        try expectEqual(session.currentWebSelectionContext, "", "adopting a document should clear previous web context")
        try expect(session.currentWebSelectionOccurrenceIndex == nil, "adopting a document should clear previous selection occurrence")
        try expect(session.currentWebSelectionRect == nil, "adopting a document should clear previous selection bounds")
        try expect(session.pendingWebProgressRestore == nil, "adopting a document should clear a pending web restoration")
        try expectEqual(session.webZoomPercent, 100, "adopting a document should reset web zoom")
        try expectEqual(session.webScrollProgress, 0, "adopting a document should reset web progress")
        try expect(session.lastPageIndex == nil, "adopting a document should clear the previous page index")
        try expect(session.acceptsLoad(generation: generation), "adopting content should preserve the active load ticket")
    }
}
