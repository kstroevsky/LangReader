import Foundation

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
