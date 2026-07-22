import Foundation

enum ShelfCardPresenterTests {
    static func testDocumentKindText() throws {
        let epub = ShelfCardPresenter.documentKindText("EPUB")
        let docx = ShelfCardPresenter.documentKindText("DOCX")
        let pdf = ShelfCardPresenter.documentKindText("PDF")

        try expect(epub != docx && docx != pdf && epub != pdf, "each document kind should read differently")
        // Anything the shelf does not recognise is opened as a PDF, so it must
        // not be labelled as something the reader will not actually show.
        try expectEqual(
            ShelfCardPresenter.documentKindText("something-else"),
            pdf,
            "an unknown kind should fall back to the PDF wording"
        )
        try expectEqual(
            ShelfCardPresenter.documentKindText(""),
            pdf,
            "an empty kind should fall back to the PDF wording"
        )
    }

    static func testProgressTextClampsToRealPercentages() throws {
        // Progress is persisted from scroll positions, which can land just
        // outside 0...1 at the extremes; showing "101% read" would be a bug.
        try expectEqual(ShelfCardPresenter.clampedPercent(1.004), 100, "over-full progress should clamp to 100")
        try expectEqual(ShelfCardPresenter.clampedPercent(-0.02), 0, "negative progress should clamp to 0")
        try expectEqual(ShelfCardPresenter.clampedPercent(0.5), 50, "half progress should read as 50")
        try expectEqual(ShelfCardPresenter.clampedPercent(0.006), 1, "small progress should round to a whole percent")
        try expectEqual(ShelfCardPresenter.clampedPercent(0.004), 0, "sub-half-percent progress should round down")
        try expectEqual(ShelfCardPresenter.clampedPercent(.nan), 0, "unusable progress should not produce a garbage percent")
        try expectEqual(ShelfCardPresenter.clampedPercent(.infinity), 0, "infinite progress should not produce a garbage percent")
        // The clamp has to happen in Double space: `Int(_:)` traps on values
        // outside Int's range, so clamping after the conversion would crash
        // here rather than pin to 100.
        try expectEqual(ShelfCardPresenter.clampedPercent(1e30), 100, "absurd progress should clamp, not trap")
        try expectEqual(ShelfCardPresenter.clampedPercent(-1e30), 0, "absurdly negative progress should clamp, not trap")
    }

    static func testProgressTextDistinguishesUnreadFromZero() throws {
        let none = ShelfCardPresenter.progressText(readingProgress: nil)
        let zero = ShelfCardPresenter.progressText(readingProgress: 0)

        // "never opened" and "opened but at the very start" are different
        // facts, and the shelf is where a reader decides what to resume.
        try expect(none != zero, "no recorded progress should read differently from 0%")
        try expect(zero.contains("0"), "zero progress should still report a percentage, got \(zero)")
        try expect(
            ShelfCardPresenter.progressText(readingProgress: 1).contains("100"),
            "complete progress should report 100%"
        )
    }
}
