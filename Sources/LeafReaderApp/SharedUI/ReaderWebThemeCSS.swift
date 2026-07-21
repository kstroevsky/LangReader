import Foundation

/// Generates the reader's web stylesheet from design tokens.
///
/// The stylesheet used to be a literal string with the palette hand-written
/// into it, which is why the web and AppKit copies of the same colour drifted.
/// Deriving every declaration from `ReaderSurfaceTokens` means a colour is
/// changed in one place, and the accompanying test asserts the output carries no
/// hard-coded colour literals so it cannot regress.
enum ReaderWebThemeCSS {
    /// Element selectors whose colour the reader overrides. Documents style
    /// these themselves, so the theme has to win — hence `!important`.
    private static let textElements = [
        "p", "div", "span", "li", "blockquote", "td", "th",
        "h1", "h2", "h3", "h4", "h5", "h6", "strong", "em", "b", "i"
    ]

    /// The class the reader puts on `<html>` for a theme, or nil for the
    /// untinted theme, which deliberately leaves documents as authored.
    static func rootClass(for theme: ReaderTheme) -> String? {
        switch theme {
        case .original: return nil
        case .eyeCare: return "leaf-reader-eye-care"
        case .dark: return "leaf-reader-dark"
        }
    }

    /// The full stylesheet: one themed block per tinted theme.
    static func stylesheet() -> String {
        ReaderTheme.allCases
            .compactMap { theme in rootClass(for: theme).map { block(for: theme, rootClass: $0) } }
            .joined(separator: "\n")
    }

    /// One theme's block, derived entirely from its tokens.
    static func block(for theme: ReaderTheme, rootClass: String) -> String {
        let tokens = theme.surfaceTokens
        let root = "html.\(rootClass)"
        let textSelectors = textElements
            .map { "\(root) \($0)" }
            .joined(separator: ",\n")

        var css = """
        \(root) { background: \(tokens.canvas.cssHex) !important; color-scheme: \(tokens.colorScheme); }
        \(root) body {
          color: \(tokens.bodyText.cssHex) !important;
          background: \(tokens.surface.cssHex) !important;
        }
        \(textSelectors) {
          color: \(tokens.bodyText.cssHex) !important;
          background-color: transparent !important;
          text-shadow: none !important;
        }
        \(root) body * {
          border-color: \(tokens.border.cssHex) !important;
        }
        \(root) a {
          color: \(tokens.link.cssHex) !important;
        }
        \(root) ::selection {
          background: \(tokens.selection.cssRGBA) !important;
        }
        """

        if let filter = tokens.imageFilter {
            css += """

            \(root) img,
            \(root) svg {
              filter: \(filter);
            }
            """
        }
        return css
    }
}
