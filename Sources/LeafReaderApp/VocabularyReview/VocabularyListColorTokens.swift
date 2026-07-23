import Foundation

/// The vocabulary-library list colours as platform-neutral tokens.
///
/// The SwiftUI word list resolved these through `Color(nsColor:)`; holding them
/// as `DesignColor`s (Foundation only) keeps the list's colour path portable to
/// iOS. `ReaderDesignTokenTests` asserts they stay equal to the `NSColor`
/// palette the AppKit detail pane still uses.
struct VocabularyListColorTokens: Equatable {
    let primaryText: DesignColor
    let secondaryText: DesignColor
    let accent: DesignColor
}

extension ReaderTheme {
    var vocabularyListColorTokens: VocabularyListColorTokens {
        switch self {
        case .original:
            return VocabularyListColorTokens(
                primaryText: DesignColor(0.10, 0.12, 0.16),
                secondaryText: DesignColor(0.48, 0.54, 0.66),
                accent: DesignColor(0.02, 0.48, 0.98)
            )
        case .eyeCare:
            return VocabularyListColorTokens(
                primaryText: DesignColor(0.16, 0.13, 0.08),
                secondaryText: DesignColor(0.45, 0.39, 0.26),
                accent: DesignColor(0.55, 0.38, 0.14)
            )
        case .dark:
            return VocabularyListColorTokens(
                primaryText: DesignColor(0.88, 0.91, 0.95),
                secondaryText: DesignColor(0.60, 0.67, 0.76),
                accent: DesignColor(0.32, 0.55, 1.00)
            )
        }
    }
}
