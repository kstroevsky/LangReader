import Foundation

/// The shelf's colours as platform-neutral tokens.
///
/// The shelf's SwiftUI view used to resolve every colour through
/// `Color(nsColor: theme.shelfXxxColor)` — an `NSColor` bridge that does not
/// exist on iOS, so the screen could not be reused there. These tokens hold the
/// same values as plain `DesignColor`s (Foundation only), and the view builds
/// its SwiftUI `Color`s from them, leaving the shelf's colour path free of any
/// UI-framework dependency.
///
/// The AppKit palette (`ReaderTheme+Palette`) still owns the `NSColor`s the
/// reader chrome draws with; `ShelfColorTokensTests` asserts these tokens stay
/// equal to it, so the two definitions cannot drift.
struct ShelfColorTokens: Equatable {
    let background: DesignColor
    let primaryText: DesignColor
    let secondaryText: DesignColor
    let border: DesignColor
    let accent: DesignColor
    let secondaryButtonBackground: DesignColor
    let primaryActionText: DesignColor
}

extension ReaderTheme {
    var shelfColorTokens: ShelfColorTokens {
        switch self {
        case .original:
            return ShelfColorTokens(
                background: DesignColor(1, 1, 1),
                primaryText: DesignColor(0.06, 0.07, 0.09),
                secondaryText: DesignColor(0.45, 0.49, 0.60),
                border: DesignColor(0.84, 0.87, 0.92),
                accent: DesignColor(0.02, 0.48, 0.98),
                secondaryButtonBackground: DesignColor(1, 1, 1),
                primaryActionText: DesignColor(1, 1, 1)
            )
        case .eyeCare:
            return ShelfColorTokens(
                background: DesignColor(0.91, 0.87, 0.74),
                primaryText: DesignColor(0.16, 0.13, 0.08),
                secondaryText: DesignColor(0.45, 0.39, 0.26),
                border: DesignColor(0.68, 0.61, 0.43),
                accent: DesignColor(0.55, 0.38, 0.14),
                secondaryButtonBackground: DesignColor(0.89, 0.84, 0.69),
                primaryActionText: DesignColor(0.97, 0.93, 0.78)
            )
        case .dark:
            return ShelfColorTokens(
                background: DesignColor(0.10, 0.12, 0.15),
                primaryText: DesignColor(0.86, 0.88, 0.92),
                secondaryText: DesignColor(0.58, 0.63, 0.70),
                border: DesignColor(0.28, 0.34, 0.42),
                accent: DesignColor(0.32, 0.55, 1.00),
                secondaryButtonBackground: DesignColor(0.10, 0.12, 0.15),
                primaryActionText: DesignColor(1, 1, 1)
            )
        }
    }
}
