import Foundation
import LeafReaderCore

/// The reader chrome's visibility rules, now that they live in one value type
/// instead of being duplicated across every document-load path.
enum ReaderChromeStateTests {
    static func testChromeStateByPresentation() throws {
        let pdf = ReaderChromeState.make(presentation: .pdf)
        try expect(pdf.showsPageLayoutButton, "PDF shows the page-layout button")
        try expect(pdf.showsCropButton, "PDF shows the crop button")
        try expect(pdf.showsRelatedFormsToggle, "PDF shows the related-forms toggle")
        try expect(pdf.showsCover, "a loaded document shows its cover")

        // Web/EPUB drive PDFKit-only and PDF-vocabulary-only controls off. This
        // is the rule that used to be duplicated by hand in three files.
        let web = ReaderChromeState.make(presentation: .web)
        try expect(!web.showsPageLayoutButton, "web hides the page-layout button")
        try expect(!web.showsCropButton, "web hides the crop button")
        try expect(!web.showsRelatedFormsToggle, "web hides the related-forms toggle")
        try expect(web.showsCover, "web documents still show a cover")

        let empty = ReaderChromeState.empty
        try expect(!empty.showsCover, "the empty reader shows no cover")
        try expect(!empty.showsPageLayoutButton, "the empty reader hides the page-layout button")
        try expect(!empty.showsCropButton, "the empty reader hides the crop button")
        try expect(!empty.showsRelatedFormsToggle, "the empty reader hides the related-forms toggle")
    }

    static func testReadAloudAndCoverConditions() throws {
        try expect(
            !ReaderChromeState.make(presentation: .pdf, isReadAloudActive: false).showsReadAloudStopButton,
            "the stop button stays hidden while nothing is being read"
        )
        try expect(
            ReaderChromeState.make(presentation: .pdf, isReadAloudActive: true).showsReadAloudStopButton,
            "the stop button appears while reading aloud"
        )
        try expect(
            !ReaderChromeState.make(presentation: .empty, isReadAloudActive: true).showsReadAloudStopButton,
            "an empty reader never shows the stop button"
        )
        // A PDF whose first page yields no thumbnail must not show an empty cover.
        try expect(
            !ReaderChromeState.make(presentation: .pdf, hasCoverImage: false).showsCover,
            "no cover image means no cover view"
        )
    }

    static func testTogglePreferenceAndKindMapping() throws {
        try expect(
            ReaderChromeState.make(presentation: .pdf, showsRelatedWordForms: true).relatedFormsToggleIsOn,
            "the toggle reflects the enabled preference"
        )
        try expect(
            !ReaderChromeState.make(presentation: .pdf, showsRelatedWordForms: false).relatedFormsToggleIsOn,
            "the toggle reflects the disabled preference"
        )
        try expectEqual(ReaderChromeState.presentation(for: .pdf), .pdf, "PDF maps to the PDF presentation")
        try expectEqual(ReaderChromeState.presentation(for: .epub), .web, "EPUB maps to the web presentation")
        try expectEqual(ReaderChromeState.presentation(for: .docx), .web, "DOCX maps to the web presentation")
    }
}
