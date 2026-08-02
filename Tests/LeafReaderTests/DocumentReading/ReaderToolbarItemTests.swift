import Foundation

/// The toolbar's composition is data, so its order and per-state membership can
/// be asserted without building any AppKit views.
enum ReaderToolbarItemTests {
    static func testClusterOrder() throws {
        try expectEqual(
            ReaderToolbarLayout.items(in: .leading).map(\.id),
            [.cover, .title],
            "the leading cluster is the cover followed by the title"
        )
        try expectEqual(
            ReaderToolbarLayout.items(in: .beforeZoom).map(\.id),
            [.relatedFormsToggle, .readAloud, .readAloudStop],
            "the related-forms toggle sits before Read, which sits before Stop"
        )
        try expectEqual(
            ReaderToolbarLayout.items(in: .trailing).map(\.id),
            [.pageLayout, .crop],
            "the trailing cluster contains only reader-specific PDF controls"
        )
        // Every control belongs to exactly one cluster.
        try expectEqual(
            ReaderToolbarLayout.items.count,
            ReaderToolbarItem.Identifier.allCases.count,
            "every toolbar control is described exactly once"
        )
    }

    static func testVisibilityFollowsChromeState() throws {
        let pdf = ReaderChromeState.make(presentation: .pdf)
        try expectEqual(
            ReaderToolbarLayout.visibleItems(in: .trailing, state: pdf),
            [.pageLayout, .crop],
            "a PDF shows its reader-specific trailing controls"
        )
        try expectEqual(
            ReaderToolbarLayout.visibleItems(in: .beforeZoom, state: pdf),
            [.relatedFormsToggle, .readAloud],
            "a PDF shows the toggle and Read, but not Stop while idle"
        )

        // Web hides the PDFKit-only controls; the survivors keep their order,
        // and the stack closes the gap rather than leaving a hole.
        let web = ReaderChromeState.make(presentation: .web)
        try expectEqual(
            ReaderToolbarLayout.visibleItems(in: .trailing, state: web),
            [],
            "web leaves native macOS window controls to manage the window"
        )
        try expectEqual(
            ReaderToolbarLayout.visibleItems(in: .beforeZoom, state: web),
            [.readAloud],
            "web hides the related-forms toggle"
        )

        try expectEqual(
            ReaderToolbarLayout.visibleItems(in: .beforeZoom, state: .make(presentation: .pdf, isReadAloudActive: true)),
            [.relatedFormsToggle, .readAloud, .readAloudStop],
            "Stop joins the cluster while reading aloud"
        )
        try expectEqual(
            ReaderToolbarLayout.visibleItems(in: .leading, state: .empty),
            [.title],
            "the empty reader shows the title but no cover"
        )
    }
}
