import Foundation
import LeafReaderCore

/// The wording on a shelf card.
///
/// These rules used to live as methods on the shelf's AppKit controller, where
/// nothing could reach them without building a window. They depend on neither
/// AppKit nor the recents store — they take the two values they actually read —
/// so they live here, testable, and stay put when the shelf's view layer moves
/// to SwiftUI.
enum ShelfCardPresenter {
    /// The card's subtitle: what kind of document this is.
    ///
    /// Unknown kinds read as PDF because that is what the reader falls back to
    /// opening them as.
    static func documentKindText(_ kind: String) -> String {
        switch kind {
        case "EPUB":
            return AppText.localized("EPUB 书籍", "EPUB Book")
        case "DOCX":
            return AppText.localized("DOCX 文稿", "DOCX Document")
        default:
            return AppText.localized("PDF 书籍", "PDF Book")
        }
    }

    /// How far through the document the reader got.
    ///
    /// Progress is clamped before it is shown: it is persisted from scroll
    /// positions, which can land marginally outside 0...1 at the extremes, and
    /// "101% read" would be a visible bug. A document with no recorded position
    /// is distinct from one recorded at 0%.
    static func progressText(readingProgress: Double?) -> String {
        guard let readingProgress else {
            return AppText.localized("未记录进度", "No progress")
        }
        let percent = clampedPercent(readingProgress)
        return AppText.localized("已读 \(percent)%", "\(percent)% read")
    }

    static func clampedPercent(_ progress: Double) -> Int {
        guard progress.isFinite else { return 0 }
        // Clamp before converting, not after. `Int(_:)` traps on anything
        // outside Int's range, so the original `min(100, max(0, Int(x)))` would
        // have crashed on a corrupt progress value rather than clamped it — the
        // conversion ran first.
        return Int((min(1, max(0, progress)) * 100).rounded())
    }
}
