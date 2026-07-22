import Foundation

/// Parsing for the two editable fields in the reader's chrome: the zoom
/// percentage and the page number.
///
/// Both rules lived inline in AppKit handlers — the zoom sanitising twice, once
/// per document kind — so what counted as valid input could not be checked
/// without a window, and the two copies could drift.
enum ReaderFieldInput {
    /// The zoom field shows "127%", and readers type into it in the shape they
    /// see. Everything decorative is stripped: the percent sign in both ASCII
    /// and fullwidth (a CJK keyboard produces "％"), and thousands separators.
    static func zoomPercent(from text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "％", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let percent = Double(cleaned), percent > 0 else { return nil }
        return percent
    }

    /// PDF and web have different usable zoom ranges — a web page reflows and
    /// stops being readable far sooner than a PDF page being magnified.
    static func clampedPDFScale(percent: Double) -> CGFloat {
        CGFloat(min(max(percent, 10), 800)) / 100
    }

    static func clampedWebZoom(percent: Int) -> Int {
        min(max(percent, 60), 220)
    }

    /// The page field shows "11 / 207", so the first run of digits is the page
    /// the reader means — parsing the whole string would fail on the label's
    /// own format.
    static func pageNumber(from text: String) -> Int? {
        guard let range = text.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return Int(text[range])
    }

    /// Converts a typed, one-based page number to an index.
    ///
    /// Out-of-range input is clamped to the document, not rejected — typing a
    /// number past the end goes to the last page. That is the existing
    /// behaviour and is preserved here deliberately; whether it should instead
    /// refuse and restore the label is a design question, not something to
    /// change as a side effect of moving the code.
    static func pageIndex(fromTyped pageNumber: Int, pageCount: Int) -> Int? {
        guard pageCount > 0 else { return nil }
        return min(max(pageNumber, 1), pageCount) - 1
    }
}
