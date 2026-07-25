import Foundation

/// How a web-backed document (EPUB, DOCX, HTML) is currently being shown: its
/// extracted text, the zoom level, and how far down it is scrolled.
///
/// Split out of `DocumentSession`, which held this alongside three unrelated
/// concerns. Platform-neutral: the values here describe *what* is shown, not
/// how, so the same state would drive a WKWebView or its iOS equivalent.
struct ReaderWebPresentation: Equatable {
    /// The whole document as plain text, used for AI context and read-aloud.
    /// Loaded asynchronously, which is what the generation counter guards.
    var plainText = ""

    /// Bumped whenever the text is invalidated, so a slow extraction that
    /// finishes after the reader moved on can be discarded rather than
    /// overwriting the new document's text.
    private(set) var plainTextGeneration = 0

    var zoomPercent = 100
    var scrollProgress: Double = 0
    /// Rate-limits how often progress is written to the session store.
    var lastProgressSave = Date.distantPast

    /// A saved position waiting for the page to finish loading. Held with the
    /// load generation it belongs to, so a restore for a previous document is
    /// dropped instead of scrolling the new one.
    var pendingProgressRestore: PendingProgressRestore?

    struct PendingProgressRestore: Equatable {
        let generation: Int
        let progress: Double
        let zoomPercent: Int?
    }

    /// Invalidates the extracted text and returns the generation that
    /// subsequent work must present to be accepted.
    @discardableResult
    mutating func invalidatePlainText() -> Int {
        plainTextGeneration += 1
        return plainTextGeneration
    }

    /// Whether asynchronous text extraction started at `generation` is still
    /// the one the reader is waiting for.
    func acceptsPlainText(generation: Int) -> Bool {
        plainTextGeneration == generation
    }

    /// Whether a pending restore belongs to the document currently loaded.
    func acceptsProgressRestore(loadGeneration: Int) -> Bool {
        pendingProgressRestore?.generation == loadGeneration
    }

    /// A cleared presentation for the next document, whose generation continues
    /// past `previous` — so extraction still running for the old document is
    /// rejected rather than landing in the new one.
    static func succeeding(_ previous: ReaderWebPresentation) -> ReaderWebPresentation {
        var next = ReaderWebPresentation()
        next.plainTextGeneration = previous.plainTextGeneration + 1
        return next
    }
}

/// Where the reader last was in the document, per document kind.
///
/// Kept apart from the web presentation because it outlives it: the page index
/// is what gets written to the session store and restored on reopen, and the
/// vocabulary buckets are used to decide when to re-offer personal words.
struct ReaderReadingPosition: Equatable {
    /// The PDF page the reader was last on.
    var lastPageIndex: Int?
    /// The page/scroll position the personal-vocabulary prompt last fired at,
    /// so it does not re-fire while the reader stays put.
    var lastPersonalVocabularyPDFPageIndex: Int?
    var lastPersonalVocabularyWebProgressBucket: Int?
}
