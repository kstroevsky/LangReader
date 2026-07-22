import Foundation

enum ReaderFieldInputTests {
    static func testZoomAcceptsWhatTheFieldItselfDisplays() throws {
        // The field shows "127%", and readers edit it in place, so its own
        // output has to parse back in.
        try expectEqual(ReaderFieldInput.zoomPercent(from: "127%"), 127, "the field's own format should parse")
        try expectEqual(ReaderFieldInput.zoomPercent(from: "127"), 127, "a bare number should parse")
        try expectEqual(ReaderFieldInput.zoomPercent(from: "  150 % "), 150, "surrounding whitespace should be ignored")
        // A CJK keyboard produces the fullwidth percent sign.
        try expectEqual(ReaderFieldInput.zoomPercent(from: "150％"), 150, "a fullwidth percent sign should parse")
        try expectEqual(ReaderFieldInput.zoomPercent(from: "1,000%"), 1000, "a thousands separator should be ignored")
    }

    static func testZoomRejectsInputThatWouldNotBeAZoom() throws {
        for text in ["", "   ", "abc", "%", "-50", "0"] {
            try expect(
                ReaderFieldInput.zoomPercent(from: text) == nil,
                "\"\(text)\" should not be accepted as a zoom"
            )
        }
    }

    static func testZoomClampsToUsableRangesPerDocumentKind() throws {
        // A web page reflows and stops being readable long before a magnified
        // PDF page does, so the two ranges differ on purpose.
        try expectEqual(ReaderFieldInput.clampedPDFScale(percent: 100), 1, "100% should be scale 1")
        try expectEqual(ReaderFieldInput.clampedPDFScale(percent: 5), 0.1, "below the floor should clamp up")
        try expectEqual(ReaderFieldInput.clampedPDFScale(percent: 5000), 8, "above the ceiling should clamp down")

        try expectEqual(ReaderFieldInput.clampedWebZoom(percent: 100), 100, "an in-range web zoom is unchanged")
        try expectEqual(ReaderFieldInput.clampedWebZoom(percent: 10), 60, "below the web floor should clamp up")
        try expectEqual(ReaderFieldInput.clampedWebZoom(percent: 900), 220, "above the web ceiling should clamp down")
    }

    static func testPageNumberIsTakenFromTheLabelsOwnFormat() throws {
        // The label reads "11 / 207"; parsing the whole string would fail on
        // the format the field itself produces.
        try expectEqual(ReaderFieldInput.pageNumber(from: "11 / 207"), 11, "the first number is the page meant")
        try expectEqual(ReaderFieldInput.pageNumber(from: "42"), 42, "a bare number should parse")
        try expectEqual(ReaderFieldInput.pageNumber(from: "  7  "), 7, "whitespace should be ignored")
        try expect(ReaderFieldInput.pageNumber(from: "no digits") == nil, "text with no digits should not parse")
        try expect(ReaderFieldInput.pageNumber(from: "") == nil, "empty text should not parse")
    }

    static func testPageIndexClampsToTheDocument() throws {
        try expectEqual(ReaderFieldInput.pageIndex(fromTyped: 1, pageCount: 207), 0, "page 1 is index 0")
        try expectEqual(ReaderFieldInput.pageIndex(fromTyped: 207, pageCount: 207), 206, "the last page is the last index")
        // Clamping is the existing behaviour, kept deliberately.
        try expectEqual(ReaderFieldInput.pageIndex(fromTyped: 9999, pageCount: 207), 206, "past the end clamps to the last page")
        try expectEqual(ReaderFieldInput.pageIndex(fromTyped: 0, pageCount: 207), 0, "below the start clamps to the first page")
        try expectEqual(ReaderFieldInput.pageIndex(fromTyped: -5, pageCount: 207), 0, "a negative page clamps to the first page")
        // An empty document has no page to go to at all.
        try expect(ReaderFieldInput.pageIndex(fromTyped: 1, pageCount: 0) == nil, "an empty document yields no index")
    }
}
