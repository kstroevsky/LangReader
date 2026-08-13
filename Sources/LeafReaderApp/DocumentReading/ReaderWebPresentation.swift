import Foundation

/// How a web-backed document (EPUB, DOCX, HTML) is currently being shown: its
/// extracted text, the zoom level, and how far down it is scrolled.
///
/// Split out of `DocumentSession`, which held this alongside three unrelated
/// concerns. Although framework-free, zoom and scroll restoration are reader
/// presentation policy and therefore belong to the app module.
package struct ReaderWebPresentation: Equatable {
    package init() {}

    /// The whole document as plain text, used for AI context and read-aloud.
    /// Loaded asynchronously, which is what the generation counter guards.
    package var plainText = ""

    /// Bumped whenever the text is invalidated, so a slow extraction that
    /// finishes after the reader moved on can be discarded rather than
    /// overwriting the new document's text.
    package private(set) var plainTextGeneration = 0

    package var zoomPercent = 100
    package var scrollProgress: Double = 0
    /// Rate-limits how often progress is written to the session store.
    package var lastProgressSave = Date.distantPast

    /// A saved position waiting for the page to finish loading. Held with the
    /// load generation it belongs to, so a restore for a previous document is
    /// dropped instead of scrolling the new one.
    package var pendingProgressRestore: PendingProgressRestore?

    package struct PendingProgressRestore: Equatable {
        package let generation: Int
        package let progress: Double
        package let zoomPercent: Int?

        package init(generation: Int, progress: Double, zoomPercent: Int?) {
            self.generation = generation
            self.progress = progress
            self.zoomPercent = zoomPercent
        }
    }

    /// Invalidates the extracted text and returns the generation that
    /// subsequent work must present to be accepted.
    @discardableResult
    package mutating func invalidatePlainText() -> Int {
        plainTextGeneration += 1
        return plainTextGeneration
    }

    /// Whether asynchronous text extraction started at `generation` is still
    /// the one the reader is waiting for.
    package func acceptsPlainText(generation: Int) -> Bool {
        plainTextGeneration == generation
    }

    /// Whether a pending restore belongs to the document currently loaded.
    package func acceptsProgressRestore(loadGeneration: Int) -> Bool {
        pendingProgressRestore?.generation == loadGeneration
    }

    /// A cleared presentation for the next document, whose generation continues
    /// past `previous` — so extraction still running for the old document is
    /// rejected rather than landing in the new one.
    package static func succeeding(_ previous: ReaderWebPresentation) -> ReaderWebPresentation {
        var next = ReaderWebPresentation()
        next.plainTextGeneration = previous.plainTextGeneration + 1
        return next
    }
}
