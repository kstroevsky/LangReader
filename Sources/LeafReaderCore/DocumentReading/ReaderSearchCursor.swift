import Foundation

/// Tracks which search hit the reader is sitting on, and how the query changed.
///
/// The rules were previously inlined at each call site: the same modular
/// arithmetic appeared four times, the "did the query change?" reset lived in
/// both the PDF and the web path, and the result label was formatted in two
/// places. None of it depends on PDFKit or WebKit — a cursor over `n` hits is
/// the same idea for both — so it lives here where it can be read in one piece
/// and tested without a document.
///
/// The cursor deliberately stores only the *count* of hits, not the hits
/// themselves: the PDF path holds `PDFSelection`s and the web path holds
/// positions inside the page, and neither belongs in shared state.
package struct ReaderSearchCursor: Equatable {
    package init() {}

    /// The query these results belong to. Empty when there is no active search.
    package private(set) var query: String = ""
    /// How many hits the current query produced.
    package private(set) var total: Int = 0
    /// Which hit is selected, zero-based. Always within `0..<total`.
    package private(set) var index: Int = 0

    package var isEmpty: Bool { total == 0 }

    /// What a fresh query should do, so callers do not re-derive it.
    package enum QueryChange: Equatable {
        /// A different query: the caller must find hits again.
        case needsSearch
        /// The same query repeated: advance to the next hit instead.
        case advance
    }

    /// Records that `newQuery` was submitted, and reports what it means.
    ///
    /// Submitting the same query again is how "find next" is spelled from the
    /// search field, which is why an unchanged query advances rather than
    /// re-running the search.
    package mutating func submit(query newQuery: String) -> QueryChange {
        guard newQuery == query else {
            query = newQuery
            total = 0
            index = 0
            return .needsSearch
        }
        return .advance
    }

    /// Records the hit count for the current query, selecting the first hit.
    package mutating func setTotal(_ newTotal: Int) {
        total = max(0, newTotal)
        index = 0
    }

    /// Adopts a one-based position reported by the web search, which counts from
    /// one and reports zero when nothing matched.
    package mutating func adoptOneBased(index oneBased: Int, total newTotal: Int) {
        total = max(0, newTotal)
        index = max(0, oneBased - 1)
        if total > 0 { index = min(index, total - 1) }
    }

    /// Moves to the next hit, wrapping past the end.
    package mutating func advance() {
        guard total > 0 else { return }
        index = (index + 1) % total
    }

    /// Moves to the previous hit, wrapping past the start.
    package mutating func retreat() {
        guard total > 0 else { return }
        index = (index - 1 + total) % total
    }

    package mutating func clear() {
        query = ""
        total = 0
        index = 0
    }

    /// The "3 / 12" label, and "0 / 0" when there is nothing to show.
    package var resultText: String {
        total > 0 ? "\(index + 1) / \(total)" : "0 / 0"
    }
}
