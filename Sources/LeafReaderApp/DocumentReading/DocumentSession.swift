import Foundation
import LeafReaderCore

/// The document-scoped state that survives while one document is open in the Reader Shell.
///
/// A load ticket and the plain-text generation make asynchronous EPUB/DOCX work harmless
/// after the reader opens another document or unloads the current one.
///
/// What is left here is document *identity and loading*. The three concerns
/// that had accumulated alongside it now live in their own value types —
/// `ReaderSelectionState`, `ReaderWebPresentation` and `ReaderReadingPosition` —
/// so a feature can read the small piece it needs instead of the whole session.
struct DocumentSession {
    var currentFileURL: URL?
    var lastSavedSessionBookmarkURL: URL?
    var currentFileMD5: String?
    var sessionStore = ReaderSessionStore(fileMD5: nil)
    var currentDocumentKind: ReaderDocumentKind = .pdf
    private(set) var documentLoadGeneration = 0
    var selection = ReaderSelectionState()
    /// Where the selection toolbar anchors. Separate from `selection` because it
    /// is presentation geometry, not what the reader picked.
    var selectionPresentation = ReaderSelectionPresentation()
    var web = ReaderWebPresentation()
    var position = ReaderReadingPosition()
    var isRestoringSession = false

    mutating func beginLoading() -> Int {
        documentLoadGeneration += 1
        return documentLoadGeneration
    }

    func acceptsLoad(generation: Int) -> Bool {
        documentLoadGeneration == generation
    }

    mutating func adopt(url: URL, kind: ReaderDocumentKind, documentID: String?) {
        resetDocumentBoundState(invalidateLoad: false)
        currentFileURL = url
        currentFileMD5 = documentID
        sessionStore = ReaderSessionStore(fileMD5: documentID)
        currentDocumentKind = kind
    }

    mutating func unload() {
        resetDocumentBoundState(invalidateLoad: true)
    }

    private mutating func resetDocumentBoundState(invalidateLoad: Bool) {
        let nextLoadGeneration = documentLoadGeneration + (invalidateLoad ? 1 : 0)
        let bookmarkURL = lastSavedSessionBookmarkURL
        let restoringSession = isRestoringSession
        let nextWeb = ReaderWebPresentation.succeeding(web)

        self = Self()
        documentLoadGeneration = nextLoadGeneration
        web = nextWeb
        lastSavedSessionBookmarkURL = bookmarkURL
        isRestoringSession = restoringSession
    }
}
