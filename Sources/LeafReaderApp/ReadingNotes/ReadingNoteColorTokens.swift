import Foundation

/// The reading-notes list colours as platform-neutral tokens.
///
/// Mirrors the shelf's `ShelfColorTokens`: the SwiftUI notes list renders colour
/// from these `DesignColor`s (Foundation only), so its colour path compiles on
/// iOS, while the AppKit note editor keeps drawing from `ReadingNoteTheme`
/// (`NSColor`). `ReaderDesignTokenTests` asserts the two stay equal.
struct ReadingNoteColorTokens: Equatable {
    let panelBackground: DesignColor
    let cardBackground: DesignColor
    let insetBackground: DesignColor
    let primaryText: DesignColor
    let secondaryText: DesignColor
    let accent: DesignColor
    let secondaryButtonBackground: DesignColor
}

extension ReaderTheme {
    var readingNoteColorTokens: ReadingNoteColorTokens {
        switch self {
        case .original:
            return ReadingNoteColorTokens(
                panelBackground: DesignColor(0.935, 0.945, 0.96),
                cardBackground: DesignColor(1, 1, 1, alpha: 0.96),
                insetBackground: DesignColor(0.91, 0.93, 0.96),
                primaryText: DesignColor(0.08, 0.09, 0.11),
                secondaryText: DesignColor(0.39, 0.43, 0.50),
                accent: DesignColor(0.02, 0.48, 0.98),
                secondaryButtonBackground: DesignColor(1, 1, 1, alpha: 0.92)
            )
        case .eyeCare:
            return ReadingNoteColorTokens(
                panelBackground: DesignColor(0.87, 0.81, 0.61),
                cardBackground: DesignColor(0.95, 0.90, 0.76, alpha: 0.92),
                insetBackground: DesignColor(0.86, 0.78, 0.55),
                primaryText: DesignColor(0.12, 0.10, 0.07),
                secondaryText: DesignColor(0.42, 0.36, 0.24),
                accent: DesignColor(0.42, 0.29, 0.08),
                secondaryButtonBackground: DesignColor(0.91, 0.84, 0.65, alpha: 0.76)
            )
        case .dark:
            return ReadingNoteColorTokens(
                panelBackground: DesignColor(0.07, 0.08, 0.10),
                cardBackground: DesignColor(0.14, 0.17, 0.22),
                insetBackground: DesignColor(0.19, 0.23, 0.29),
                primaryText: DesignColor(0.86, 0.89, 0.94),
                secondaryText: DesignColor(0.68, 0.72, 0.78),
                accent: DesignColor(0.32, 0.55, 1.00),
                secondaryButtonBackground: DesignColor(0.18, 0.22, 0.28)
            )
        }
    }
}
