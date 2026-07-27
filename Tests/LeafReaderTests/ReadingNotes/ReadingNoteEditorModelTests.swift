import Foundation
import LeafReaderCore

/// The note editor's non-view logic. None of this was reachable from a test
/// before: the status line was raw assignments to a label, and the AI request
/// lifecycle lived in a struct that also held an event monitor.
enum ReadingNoteEditorModelTests {
    private static func note(
        markdown: String = "# Note",
        favorite: Bool = false,
        pdfPage: Int? = nil,
        scrollProgress: Double? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 0)
    ) -> ReadingNote {
        var locator = ReadingNote.Locator()
        if let pdfPage {
            locator.pdfFragments = [ReadingNote.PDFFragment(
                pageIndex: pdfPage,
                bounds: StoredPDFWordRect(CGRect(x: 0, y: 0, width: 1, height: 1))
            )]
        }
        if let scrollProgress {
            locator.webAnchor = ReadingNote.WebAnchor(
                selectedText: "",
                context: "",
                occurrenceIndex: nil,
                scrollProgress: scrollProgress
            )
        }
        return ReadingNote(
            id: "n1",
            documentID: "d1",
            documentTitle: "Doc",
            documentKind: "pdf",
            quote: "quote",
            markdown: markdown,
            locator: locator,
            createdAt: createdAt,
            updatedAt: createdAt,
            isFavorite: favorite
        )
    }

    static func testCommitFoldsTextIntoTheNoteAndClearsTheDirtyFlag() throws {
        let model = ReadingNoteEditorModel(note: note(markdown: "old"))
        try expectEqual(model.hasUnsavedChanges, false, "a freshly opened note is clean")

        model.userDidEdit("new body")
        try expectEqual(model.hasUnsavedChanges, true, "editing marks it dirty")

        let stamped = Date(timeIntervalSince1970: 1_000)
        let saved = model.commitEdits(markdown: "new body", now: stamped)

        try expectEqual(saved.markdown, "new body", "the edit should land in the note")
        try expectEqual(saved.updatedAt, stamped, "saving should stamp the note")
        try expectEqual(model.hasUnsavedChanges, false, "saving clears the dirty flag")
    }

    static func testWordCountIgnoresSurroundingWhitespace() throws {
        let model = ReadingNoteEditorModel(note: note(markdown: ""))
        model.syncText("  \n abc \n ")
        try expectEqual(model.wordCountText.hasPrefix("3"), true, "expected 3, got \(model.wordCountText)")

        model.syncText("   ")
        try expectEqual(model.wordCountText.hasPrefix("0"), true, "whitespace only should count zero")
    }

    static func testLocationTextPrefersThePDFPage() throws {
        let pdf = ReadingNoteEditorModel(note: note(pdfPage: 4, scrollProgress: 0.5))
        try expectEqual(pdf.locationText.contains("5"), true, "page index should be shown 1-based")

        let web = ReadingNoteEditorModel(note: note(scrollProgress: 0.42))
        try expectEqual(web.locationText.contains("42"), true, "web notes should show a percentage")

        let neither = ReadingNoteEditorModel(note: note())
        try expectEqual(neither.locationText.contains("0"), true, "a note with no locator should not crash")
    }

    static func testFavouriteTogglesTheNoteAndReportsIt() throws {
        let model = ReadingNoteEditorModel(note: note(favorite: false))

        let favorited = model.toggleFavorite()
        try expectEqual(favorited.isFavorite, true, "toggling should favourite it")
        try expectEqual(model.isFavorite, true, "the model should agree")
        try expectEqual(model.statusMessage.isEmpty, false, "the status line should say so")

        let unfavorited = model.toggleFavorite()
        try expectEqual(unfavorited.isFavorite, false, "toggling again should clear it")
    }

    static func testOnlyTheNewestAIResultMayBeApplied() throws {
        let model = ReadingNoteEditorModel(note: note())

        let first = model.beginAIRequest()
        try expectEqual(model.canApplyAIResult(first), true, "the live request may apply")
        try expectEqual(model.isRunningAIRequest, true, "a request is in flight")

        // A second action started before the first came back: the first must not
        // overwrite the second's answer.
        let second = model.beginAIRequest()
        try expectEqual(model.canApplyAIResult(first), false, "a superseded request must not apply")
        try expectEqual(model.canApplyAIResult(second), true, "the newest request may apply")

        model.finishAIRequest(first)
        try expectEqual(model.canApplyAIResult(second), true, "finishing an old request must not clear the new one")

        model.finishAIRequest(second)
        try expectEqual(model.canApplyAIResult(second), false, "a finished request must not apply again")
        try expectEqual(model.isRunningAIRequest, false, "nothing left in flight")
    }

    static func testAClosingEditorRefusesLateAIResults() throws {
        let model = ReadingNoteEditorModel(note: note())
        let request = model.beginAIRequest()

        model.isClosing = true

        try expectEqual(model.canApplyAIResult(request), false, "a closing editor must not be written into")
    }

    static func testReplacingTheNoteResetsTheEditor() throws {
        let model = ReadingNoteEditorModel(note: note(markdown: "first"))
        model.userDidEdit("edited")

        model.replaceNote(note(markdown: "second"))

        try expectEqual(model.text, "second", "the editor should show the new note")
        try expectEqual(model.hasUnsavedChanges, false, "a replaced note starts clean")
    }

    /// Regression: the controller used to keep its own `note` alongside this
    /// model. Favouriting from the notes list wrote that copy, but `save()`
    /// persisted the model's — so the next keystroke saved `isFavorite: false`
    /// over the change. The favourite is set on the model now, so a later commit
    /// carries it.
    static func testAnExternalFavouriteSurvivesTheNextCommit() throws {
        let model = ReadingNoteEditorModel(note: note(markdown: "body", favorite: false))

        model.setFavorite(true)
        model.userDidEdit("body edited")
        let saved = model.commitEdits(markdown: "body edited")

        try expectEqual(saved.isFavorite, true, "the commit must carry the favourite set outside the editor")
        try expectEqual(saved.markdown, "body edited", "the commit must still carry the editor's text")
    }

    /// Regression for the always-dirty flag: `commitEditorChange()` saves and
    /// *then* refreshes derived state, and the refresh pushes the same text back
    /// in. While that went through the same assignment as typing, a note was
    /// marked unsaved the instant it had been saved.
    static func testRefreshingTheTextAfterSavingLeavesTheNoteClean() throws {
        let model = ReadingNoteEditorModel(note: note(markdown: "body"))
        model.userDidEdit("body edited")
        _ = model.commitEdits(markdown: "body edited")

        model.syncText("body edited")

        try expectEqual(model.hasUnsavedChanges, false, "a refresh after saving must not re-dirty the note")
    }

    /// Typing that produces the text already held is not an edit.
    static func testReassigningTheSameTextDoesNotDirtyTheNote() throws {
        let model = ReadingNoteEditorModel(note: note(markdown: "same"))
        model.syncText("same")

        model.userDidEdit("same")

        try expectEqual(model.hasUnsavedChanges, false, "an identical assignment is not an edit")
    }

    /// The word count reports what the reader sees, so it counts the rendered
    /// text — not the markdown source that gets persisted.
    static func testCommitPersistsMarkdownRatherThanTheDisplayedText() throws {
        let model = ReadingNoteEditorModel(note: note(markdown: "old"))
        model.syncText("bold")

        let saved = model.commitEdits(markdown: "**bold**")

        try expectEqual(saved.markdown, "**bold**", "the markdown source must be persisted")
        try expectEqual(model.wordCountText.hasPrefix("4"), true,
                        "the count should describe the displayed text, got \(model.wordCountText)")
    }

    /// The list sends the state it wants, not a flip, so the two cannot disagree
    /// about which way to go.
    static func testSettingFavouriteIsIdempotent() throws {
        let model = ReadingNoteEditorModel(note: note(favorite: true))

        model.setFavorite(true)

        try expectEqual(model.note.isFavorite, true, "setting an already-set favourite must not clear it")
    }
}
