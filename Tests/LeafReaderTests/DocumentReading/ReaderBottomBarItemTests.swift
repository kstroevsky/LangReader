import Foundation
import LeafReaderCore

enum ReaderBottomBarItemTests {
    static func testEveryControlIsPlacedExactlyOnce() throws {
        let ids = ReaderBottomBarLayout.items.map(\.id)
        try expectEqual(
            Set(ids).count,
            ids.count,
            "no control should appear twice in the bar"
        )
        // A control that exists but is in no layout is one the reader can never
        // reach — the failure the descriptor list is meant to make impossible.
        for id in ReaderBottomBarItem.Identifier.allCases {
            try expect(ids.contains(id), "\(id.rawValue) is not placed in the bar")
        }
    }

    static func testNavigationGroupIsInReadingOrder() throws {
        try expectEqual(
            ReaderBottomBarLayout.items(in: .navigation).map(\.id),
            [.toc],
            "cross-document navigation should be consolidated in the TOC and page field"
        )
    }

    static func testPanelButtonsComeAfterSettingsAndKeepTheirOrder() throws {
        let ids = ReaderBottomBarLayout.items.map(\.id)
        let settingsIndex = ids.firstIndex(of: .settings)
        let shelfIndex = ids.firstIndex(of: .shelf)
        try expect(settingsIndex != nil && shelfIndex != nil, "settings and shelf should both be placed")
        try expect((settingsIndex ?? 0) < (shelfIndex ?? 0), "the gear should lead the bar")
        try expectEqual(
            ReaderBottomBarLayout.items(in: .panels).map(\.id),
            [.shelf, .words, .review, .notes],
            "the panel buttons should match the on-screen order: Shelf, Words, Review, Notes"
        )
    }

    static func testOnlyAnalysisControlsAreTransient() throws {
        // Everything else is always on the bar; if a normal button were marked
        // transient it would silently vanish from the reader's chrome.
        let transient = ReaderBottomBarLayout.items.filter(\.isTransient).map(\.id)
        try expectEqual(
            Set(transient),
            Set([.embeddingPause, .embeddingCancel]),
            "only the AI-analysis controls should be transient"
        )
    }

    static func testOnlyPanelButtonsCarryALeadingSymbol() throws {
        // The navigation buttons sit together and read as a unit, so a symbol
        // on each adds noise rather than meaning.
        for item in ReaderBottomBarLayout.items(in: .navigation) {
            try expect(!item.showsLeadingSymbol, "\(item.id.rawValue) should not draw a leading symbol")
        }
        for item in ReaderBottomBarLayout.items(in: .panels) {
            try expect(item.showsLeadingSymbol, "\(item.id.rawValue) should draw a leading symbol")
        }
    }
}
