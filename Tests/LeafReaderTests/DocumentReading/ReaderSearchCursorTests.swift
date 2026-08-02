import Foundation
import LeafReaderCore

/// The search cursor's rules, previously inlined at each call site as modular
/// arithmetic and duplicated query-reset checks.
enum ReaderSearchCursorTests {
    static func testSubmitDistinguishesNewQueryFromFindNext() throws {
        var cursor = ReaderSearchCursor()
        try expectEqual(cursor.submit(query: "wort"), .needsSearch, "a first query needs a search")
        cursor.setTotal(3)
        // Re-submitting the same query is how the search field spells "find next".
        try expectEqual(cursor.submit(query: "wort"), .advance, "an unchanged query advances instead of re-searching")
        try expectEqual(cursor.total, 3, "advancing keeps the existing hits")
        // A different query invalidates the previous results.
        try expectEqual(cursor.submit(query: "andere"), .needsSearch, "a changed query needs a search")
        try expectEqual(cursor.total, 0, "a changed query drops the stale hit count")
        try expectEqual(cursor.index, 0, "a changed query returns to the first hit")
    }

    static func testWrapsInBothDirections() throws {
        var cursor = ReaderSearchCursor()
        _ = cursor.submit(query: "wort")
        cursor.setTotal(3)
        try expectEqual(cursor.index, 0, "a fresh search selects the first hit")
        cursor.advance(); try expectEqual(cursor.index, 1, "advance moves forward")
        cursor.advance(); try expectEqual(cursor.index, 2, "advance moves forward again")
        cursor.advance(); try expectEqual(cursor.index, 0, "advance wraps past the end")
        cursor.retreat(); try expectEqual(cursor.index, 2, "retreat wraps past the start")
        cursor.retreat(); try expectEqual(cursor.index, 1, "retreat moves backward")
    }

    static func testEmptyResultsAreInert() throws {
        var cursor = ReaderSearchCursor()
        _ = cursor.submit(query: "missing")
        cursor.setTotal(0)
        try expect(cursor.isEmpty, "no hits means empty")
        // Navigating an empty result set must not produce a negative or
        // out-of-range index for the caller to index an array with.
        cursor.advance(); try expectEqual(cursor.index, 0, "advancing with no hits stays put")
        cursor.retreat(); try expectEqual(cursor.index, 0, "retreating with no hits stays put")
        try expectEqual(cursor.resultText, "0 / 0", "an empty search reads 0 / 0")
    }

    static func testResultTextIsOneBased() throws {
        var cursor = ReaderSearchCursor()
        _ = cursor.submit(query: "wort")
        cursor.setTotal(12)
        try expectEqual(cursor.resultText, "1 / 12", "the label counts from one")
        cursor.advance()
        cursor.advance()
        try expectEqual(cursor.resultText, "3 / 12", "the label follows the cursor")
    }

    /// The web path reports a one-based index, and zero when nothing matched.
    static func testAdoptOneBasedFromWebSearch() throws {
        var cursor = ReaderSearchCursor()
        _ = cursor.submit(query: "wort")
        cursor.adoptOneBased(index: 3, total: 9)
        try expectEqual(cursor.index, 2, "a one-based index becomes zero-based")
        try expectEqual(cursor.resultText, "3 / 9", "the label round-trips")

        cursor.adoptOneBased(index: 0, total: 0)
        try expectEqual(cursor.index, 0, "a miss reports no hit rather than index -1")
        try expectEqual(cursor.resultText, "0 / 0", "a miss reads 0 / 0")

        // An out-of-range report must not escape the valid range.
        cursor.adoptOneBased(index: 99, total: 4)
        try expectEqual(cursor.index, 3, "an over-large index clamps to the last hit")
    }

    static func testClearResetsEverything() throws {
        var cursor = ReaderSearchCursor()
        _ = cursor.submit(query: "wort")
        cursor.setTotal(5)
        cursor.advance()
        cursor.clear()
        try expectEqual(cursor, ReaderSearchCursor(), "clear returns the cursor to its initial state")
        // After clearing, the previous query must not be mistaken for a repeat.
        try expectEqual(cursor.submit(query: "wort"), .needsSearch, "the cleared query searches again")
    }
}
