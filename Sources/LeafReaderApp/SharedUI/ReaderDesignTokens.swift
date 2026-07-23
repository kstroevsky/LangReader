import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif

/// One colour in the design system, defined once and rendered for any surface.
///
/// The reader draws to several very different canvases — AppKit chrome, a
/// WebKit-hosted document, and SwiftUI screens — and each once carried its own
/// copy of the palette: `NSColor(red:green:blue:)` here, hex literals in a CSS
/// string there, `Color(nsColor:)` in the SwiftUI views. Nothing kept them in
/// step, so the same concept drifted (dark body text was `rgb(0.82, 0.85, 0.90)`
/// in the chrome and `#d9dee7` on the page). Defining the colour once as plain
/// components and deriving every representation removes that drift.
///
/// The type is platform-neutral by construction — it stores only numbers and
/// imports Foundation. The `nsColor` and `color` accessors are compiled only
/// where their frameworks exist, so the same token vends an `NSColor` to AppKit,
/// a SwiftUI `Color` to any SwiftUI view (macOS *or* iOS), and CSS to the web
/// reader, without the storage ever depending on a UI framework.
struct DesignColor: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(_ red: Double, _ green: Double, _ blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Builds a token from a CSS hex string (`#rrggbb`), so values that were
    /// authored as hex keep their exact appearance when they move here.
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(
            Double((number >> 16) & 0xFF) / 255,
            Double((number >> 8) & 0xFF) / 255,
            Double(number & 0xFF) / 255
        )
    }

    private var channels: (Int, Int, Int) {
        (
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    /// `#rrggbb`, for CSS declarations that take an opaque colour.
    var cssHex: String {
        let (r, g, b) = channels
        return String(format: "#%02x%02x%02x", r, g, b)
    }

    /// `rgba(r, g, b, a)`, for CSS declarations that need the alpha.
    var cssRGBA: String {
        let (r, g, b) = channels
        return String(format: "rgba(%d, %d, %d, %.3f)", r, g, b, alpha)
    }

    #if canImport(AppKit)
    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
    #endif

    #if canImport(SwiftUI)
    /// The SwiftUI colour, in sRGB — the same space `nsColor` uses, so a token
    /// looks the same whether a view renders it through AppKit or SwiftUI, on
    /// macOS or iOS.
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
    #endif

    func withAlpha(_ newAlpha: Double) -> DesignColor {
        DesignColor(red, green, blue, alpha: newAlpha)
    }
}

/// The colours shared by the AppKit chrome and the web reader for one theme.
///
/// Scope is deliberately the *reading surface* — the canvas, the page, body
/// text, rules, links and selection. Chrome-only colours stay in
/// `ReaderTheme+Palette`; they have no web counterpart, and folding them in
/// would imply a correspondence that does not exist (a toolbar label and a
/// paragraph of body text are different roles that merely look similar).
struct ReaderSurfaceTokens: Equatable {
    /// Behind the page — the window canvas the document sits on.
    let canvas: DesignColor
    /// The page itself.
    let surface: DesignColor
    /// Body copy.
    let bodyText: DesignColor
    /// Rules, table borders and dividers inside the document.
    let border: DesignColor
    /// Hyperlinks.
    let link: DesignColor
    /// Text-selection highlight, alpha included.
    let selection: DesignColor
    /// `color-scheme`, so form controls and scrollbars match the theme.
    let colorScheme: String
    /// Optional CSS filter applied to document images, to stop them glaring.
    let imageFilter: String?

    static func tokens(for theme: ReaderTheme) -> ReaderSurfaceTokens {
        switch theme {
        case .original:
            // The untinted theme leaves the document's own styling alone; the
            // tokens describe the default page so other surfaces can match it.
            return ReaderSurfaceTokens(
                canvas: DesignColor(1, 1, 1),
                surface: DesignColor(1, 1, 1),
                bodyText: DesignColor(0.10, 0.11, 0.14),
                border: DesignColor(0.85, 0.87, 0.90),
                link: DesignColor(0.02, 0.48, 0.98),
                selection: DesignColor(1.0, 0.867, 0.341, alpha: 0.46),
                colorScheme: "light",
                imageFilter: nil
            )
        case .eyeCare:
            return ReaderSurfaceTokens(
                canvas: DesignColor(hex: "#eee8d5") ?? DesignColor(0.93, 0.91, 0.84),
                surface: DesignColor(hex: "#f3eddb") ?? DesignColor(0.95, 0.93, 0.86),
                bodyText: DesignColor(hex: "#24261f") ?? DesignColor(0.14, 0.15, 0.12),
                border: DesignColor(hex: "#d8cda9") ?? DesignColor(0.85, 0.80, 0.66),
                link: DesignColor(hex: "#315d93") ?? DesignColor(0.19, 0.36, 0.58),
                selection: DesignColor(0.80, 0.584, 0.153, alpha: 0.30),
                colorScheme: "light",
                imageFilter: "brightness(.94) saturate(.92) contrast(.98)"
            )
        case .dark:
            return ReaderSurfaceTokens(
                canvas: DesignColor(hex: "#111418") ?? DesignColor(0.07, 0.08, 0.09),
                surface: DesignColor(hex: "#171a20") ?? DesignColor(0.09, 0.10, 0.13),
                bodyText: DesignColor(hex: "#d9dee7") ?? DesignColor(0.85, 0.87, 0.91),
                border: DesignColor(hex: "#343b46") ?? DesignColor(0.20, 0.23, 0.27),
                link: DesignColor(hex: "#9fc0ff") ?? DesignColor(0.62, 0.75, 1.0),
                selection: DesignColor(1.0, 0.867, 0.341, alpha: 0.46),
                colorScheme: "dark",
                imageFilter: "brightness(.88) contrast(.98)"
            )
        }
    }
}

extension ReaderTheme {
    /// The reading-surface tokens for this theme.
    var surfaceTokens: ReaderSurfaceTokens {
        ReaderSurfaceTokens.tokens(for: self)
    }
}
