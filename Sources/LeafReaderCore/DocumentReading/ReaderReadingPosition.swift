/// Where the reader last was in the document, per document kind.
///
/// This state outlives the current presentation: the page index is persisted
/// and restored on reopen, and the vocabulary buckets decide when to re-offer
/// personal words. Those are document/session semantics rather than window or
/// rendering facts, so they remain in Core.
package struct ReaderReadingPosition: Equatable {
    package init() {}

    /// The PDF page the reader was last on.
    package var lastPageIndex: Int?
    /// The page/scroll position the personal-vocabulary prompt last fired at,
    /// so it does not re-fire while the reader stays put.
    package var lastPersonalVocabularyPDFPageIndex: Int?
    package var lastPersonalVocabularyWebProgressBucket: Int?
}
