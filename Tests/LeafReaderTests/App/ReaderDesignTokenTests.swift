import Foundation
import Cocoa

/// The shared design-token layer: one definition per colour, rendered for both
/// AppKit and the web stylesheet.
enum ReaderDesignTokenTests {
    static func testColorRendering() throws {
        let color = DesignColor(hex: "#d9dee7")
        try expect(color != nil, "a six-digit hex string parses")
        try expectEqual(color?.cssHex, "#d9dee7", "hex round-trips through the token")
        try expectEqual(color?.cssRGBA, "rgba(217, 222, 231, 1.000)", "rgba renders every channel")
        try expectEqual(DesignColor(1, 1, 1).cssHex, "#ffffff", "white renders as #ffffff")
        try expectEqual(DesignColor(0, 0, 0).cssHex, "#000000", "black renders as #000000")
        try expectEqual(
            DesignColor(1.0, 0.867, 0.341, alpha: 0.46).cssRGBA,
            "rgba(255, 221, 87, 0.460)",
            "alpha survives into the rgba form"
        )
        try expectEqual(DesignColor(1, 1, 1).withAlpha(0.5).alpha, 0.5, "withAlpha changes only the alpha")

        // Malformed input is rejected rather than silently producing black.
        try expect(DesignColor(hex: "#fff") == nil, "a three-digit hex is rejected")
        try expect(DesignColor(hex: "nonsense") == nil, "a non-hex string is rejected")

        // The AppKit representation matches the CSS one.
        let ns = DesignColor(hex: "#111418")!.nsColor.usingColorSpace(.sRGB)
        try expectEqual(Int(((ns?.redComponent ?? 0) * 255).rounded()), 0x11, "red channel survives the AppKit bridge")
        try expectEqual(Int(((ns?.greenComponent ?? 0) * 255).rounded()), 0x14, "green channel survives the AppKit bridge")
        try expectEqual(Int(((ns?.blueComponent ?? 0) * 255).rounded()), 0x18, "blue channel survives the AppKit bridge")
    }

    static func testEveryThemeHasSurfaceTokens() throws {
        for theme in ReaderTheme.allCases {
            let tokens = theme.surfaceTokens
            try expect(!tokens.colorScheme.isEmpty, "\(theme.rawValue) declares a color-scheme")
            try expect(
                tokens.colorScheme == "dark" || tokens.colorScheme == "light",
                "\(theme.rawValue) uses a valid color-scheme"
            )
            try expect(tokens.selection.alpha > 0, "\(theme.rawValue) has a visible selection colour")
        }
        // The untinted theme deliberately leaves documents as authored.
        try expect(ReaderWebThemeCSS.rootClass(for: .original) == nil, "the untinted theme has no root class")
        try expect(ReaderWebThemeCSS.rootClass(for: .dark) != nil, "the dark theme has a root class")
        try expect(ReaderWebThemeCSS.rootClass(for: .eyeCare) != nil, "the eye-care theme has a root class")
    }

    /// The point of the layer: every colour in the stylesheet traces back to a
    /// token. If someone hand-writes one, this fails.
    static func testStylesheetContainsNoUntrackedColours() throws {
        let css = ReaderWebThemeCSS.stylesheet()
        try expect(!css.isEmpty, "the stylesheet is generated")

        var allowed = Set<String>()
        for theme in ReaderTheme.allCases {
            let tokens = theme.surfaceTokens
            for color in [tokens.canvas, tokens.surface, tokens.bodyText, tokens.border, tokens.link, tokens.selection] {
                allowed.insert(color.cssHex)
                allowed.insert(color.cssRGBA)
            }
        }

        // Every hex literal present must be one a token produced.
        let hexPattern = try NSRegularExpression(pattern: "#[0-9a-fA-F]{6}")
        let range = NSRange(css.startIndex..<css.endIndex, in: css)
        for match in hexPattern.matches(in: css, range: range) {
            guard let matchRange = Range(match.range, in: css) else { continue }
            let literal = String(css[matchRange]).lowercased()
            try expect(allowed.contains(literal), "colour \(literal) in the stylesheet must come from a token")
        }
        // Same for rgba() literals.
        let rgbaPattern = try NSRegularExpression(pattern: "rgba\\([^)]*\\)")
        for match in rgbaPattern.matches(in: css, range: range) {
            guard let matchRange = Range(match.range, in: css) else { continue }
            let literal = String(css[matchRange])
            try expect(allowed.contains(literal), "colour \(literal) in the stylesheet must come from a token")
        }
    }

    /// The shelf's platform-neutral colour tokens must stay equal to the AppKit
    /// palette the reader chrome still draws with.
    ///
    /// The shelf's SwiftUI view now renders colour from `ShelfColorTokens`
    /// (`DesignColor`, no `NSColor`) so it compiles on iOS, while the AppKit
    /// chrome renders from `ReaderTheme+Palette` (`NSColor`). Two definitions of
    /// the same colour can drift; this fails the build if they do.
    static func testScreenColorTokensMatchTheAppKitPalette() throws {
        for theme in ReaderTheme.allCases {
            let shelf = theme.shelfColorTokens
            try assertMatch(shelf.background, theme.shelfBackgroundColor, theme, "shelf background")
            try assertMatch(shelf.primaryText, theme.shelfPrimaryTextColor, theme, "shelf primaryText")
            try assertMatch(shelf.secondaryText, theme.shelfSecondaryTextColor, theme, "shelf secondaryText")
            try assertMatch(shelf.border, theme.shelfBorderColor, theme, "shelf border")
            try assertMatch(shelf.accent, theme.accentColor, theme, "shelf accent")
            try assertMatch(shelf.secondaryButtonBackground, theme.shelfButtonBackgroundColor, theme, "shelf secondaryButtonBackground")
            try assertMatch(shelf.primaryActionText, theme.primaryActionTextColor, theme, "shelf primaryActionText")

            let notes = theme.readingNoteColorTokens
            try assertMatch(notes.panelBackground, ReadingNoteTheme.panelBackground(theme), theme, "note panelBackground")
            try assertMatch(notes.cardBackground, ReadingNoteTheme.cardBackground(theme), theme, "note cardBackground")
            try assertMatch(notes.insetBackground, ReadingNoteTheme.insetBackground(theme), theme, "note insetBackground")
            try assertMatch(notes.primaryText, ReadingNoteTheme.primaryText(theme), theme, "note primaryText")
            try assertMatch(notes.secondaryText, ReadingNoteTheme.secondaryText(theme), theme, "note secondaryText")
            try assertMatch(notes.accent, ReadingNoteTheme.accent(theme), theme, "note accent")
            try assertMatch(notes.secondaryButtonBackground, ReadingNoteTheme.secondaryButtonBackground(theme), theme, "note secondaryButtonBackground")

            let vocab = theme.vocabularyListColorTokens
            try assertMatch(vocab.primaryText, theme.vocabularyPrimaryTextColor, theme, "vocab primaryText")
            try assertMatch(vocab.secondaryText, theme.vocabularySecondaryTextColor, theme, "vocab secondaryText")
            try assertMatch(vocab.accent, theme.accentColor, theme, "vocab accent")
        }
    }

    /// Asserts a token equals an `NSColor`, both read in sRGB. A one-count
    /// tolerance absorbs the rounding of the colour-space conversion; a real
    /// value drift is far larger than one 8-bit step.
    private static func assertMatch(
        _ token: DesignColor,
        _ nsColor: NSColor,
        _ theme: ReaderTheme,
        _ label: String
    ) throws {
        try expect(nsColor.usingColorSpace(.sRGB) != nil, "\(theme) \(label): NSColor has no sRGB form")
        let srgb = nsColor.usingColorSpace(.sRGB)!
        let expected = [srgb.redComponent, srgb.greenComponent, srgb.blueComponent, srgb.alphaComponent]
        let actual = [token.red, token.green, token.blue, token.alpha]
        for (channel, pair) in zip(["r", "g", "b", "a"], zip(expected, actual)) {
            let delta = abs(Double(pair.0) - pair.1)
            try expect(
                delta <= 1.0 / 255.0,
                "\(theme) shelf \(label) \(channel): token \(pair.1) drifted from palette \(pair.0)"
            )
        }
    }

    /// The generated stylesheet must still say what the hand-written one said.
    static func testStylesheetMatchesKnownAppearance() throws {
        let css = ReaderWebThemeCSS.stylesheet()
        for expected in [
            "html.leaf-reader-dark { background: #111418 !important; color-scheme: dark; }",
            "color: #d9dee7 !important;",
            "border-color: #343b46 !important;",
            "color: #9fc0ff !important;",
            "background: rgba(255, 221, 87, 0.460) !important;",
            "html.leaf-reader-eye-care { background: #eee8d5 !important; color-scheme: light; }",
            "color: #24261f !important;",
            "border-color: #d8cda9 !important;",
            "color: #315d93 !important;",
            "filter: brightness(.88) contrast(.98);",
            "filter: brightness(.94) saturate(.92) contrast(.98);"
        ] {
            try expect(css.contains(expected), "the stylesheet keeps its established appearance: \(expected)")
        }
        try expect(!css.contains("leaf-reader-original"), "the untinted theme contributes no rules")
    }
}
