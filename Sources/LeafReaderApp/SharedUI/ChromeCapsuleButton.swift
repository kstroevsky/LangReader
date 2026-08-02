import SwiftUI

// The reader's capsule button and its palette. These are shared by the bottom
// bar, the top toolbar and the AI panel's header, so they live here rather than
// inside whichever screen happened to need them first.
//
// The filename matters: `scripts/run_tests.sh` picks its logic sources by name,
// and `*Button.swift` is one of the patterns it skips. A SwiftUI view file that
// slips through that filter fails the logic build, because the theme types it
// depends on are themselves excluded.

/// A SwiftUI capsule chrome button matching `CapsuleChromeButton`'s appearance
/// (rounded rect, themed fill/stroke/text, optional leading symbol).
struct ChromeCapsuleButton: View {
    let title: String
    let symbol: String?
    let palette: ChromeCapsulePalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(palette.text)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.fill, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// The capsule button colours per theme, matching `CapsuleChromeButton.draw`.
struct ChromeCapsulePalette {
    let fill: Color
    let stroke: Color
    let text: Color
    let iconTint: Color

    init(theme: ReaderTheme) {
        switch theme {
        case .dark:
            fill = Color(red: 0.09, green: 0.11, blue: 0.15)
            stroke = Color(red: 0.22, green: 0.27, blue: 0.33)
            text = Color(red: 0.86, green: 0.89, blue: 0.94)
        case .eyeCare:
            fill = Color(red: 0.88, green: 0.82, blue: 0.66)
            stroke = Color(red: 0.66, green: 0.60, blue: 0.43)
            text = Color(red: 0.18, green: 0.15, blue: 0.09)
        case .original:
            fill = Color(red: 1, green: 1, blue: 1)
            stroke = Color(red: 0.82, green: 0.85, blue: 0.90)
            text = Color(red: 0.12, green: 0.14, blue: 0.18)
        }
        iconTint = Color(nsColor: theme.secondaryTextColor)
    }
}
