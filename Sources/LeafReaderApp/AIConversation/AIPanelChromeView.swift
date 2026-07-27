import Combine
import SwiftUI
import LeafReaderCore

/// State behind the AI panel's chrome — the header actions and the status row.
///
/// Same shape as `ReaderTopBarModel` / `ReaderBottomBarModel`: the panel pushes
/// state in, the views render from it, and taps come back through `action`.
/// Everything that is *content* — the transcript bubbles and the follow-up
/// text — stays with the AppKit panel, because both are selectable/editable
/// text and so cannot live inside an `NSHostingView`.
@Observable
final class AIPanelChromeModel {
    var theme: ReaderTheme = ReaderTheme.selected
    /// Bumped when the interface language changes, to force the AppText-derived
    /// titles to re-render.
    var languageToken: Int = 0

    // Header.
    /// The current selection, echoed inside the ask button.
    var askPreviewText: String = ""
    var askEnabled: Bool = false
    /// Summarize and Translate, disabled while a request is in flight.
    var contentActionsEnabled: Bool = true

    // Status row.
    var statusText: String = ""
    /// Drives the animated dots and the cancel button together, exactly as
    /// `setBusy` drove their `isHidden` before.
    var isBusy: Bool = false

    @ObservationIgnored var action: ((AIPanelChromeButton) -> Void)?
}

/// The AI panel chrome's tappable controls.
enum AIPanelChromeButton {
    case ask
    case summarize
    case translate
    case export
    case cancelRequest

    var accessibilityIdentifier: String {
        switch self {
        case .ask: return "aiPanel.ask"
        case .summarize: return "aiPanel.summarize"
        case .translate: return "aiPanel.translate"
        case .export: return "aiPanel.export"
        case .cancelRequest: return "aiPanel.cancelRequest"
        }
    }
}

/// Metrics shared by the SwiftUI chrome and the AppKit constraints that place
/// its hosting views, so the two cannot drift.
enum AIPanelChromeLayout {
    static let horizontalInset: CGFloat = 16
    static let topInset: CGFloat = 16
    static let askHeight: CGFloat = 44
    static let askToActionsGap: CGFloat = 10
    static let actionHeight: CGFloat = 32
    static let actionSpacing: CGFloat = 8
    static let statusHeight: CGFloat = 18
    static let dotsWidth: CGFloat = 22
    static let cancelSize: CGFloat = 22

    /// Total height of the header hosting view.
    static var headerHeight: CGFloat {
        topInset + askHeight + askToActionsGap + actionHeight
    }
}

/// The AI panel's header: the ask button plus the summarize / translate /
/// export row.
struct AIPanelHeaderView: View {
    @Bindable var model: AIPanelChromeModel

    private var colors: AIPanelColors { AIPanelColors(theme: model.theme) }
    private var palette: ChromeCapsulePalette { ChromeCapsulePalette(theme: model.theme) }

    var body: some View {
        VStack(spacing: AIPanelChromeLayout.askToActionsGap) {
            AIPanelAskButton(
                previewText: model.askPreviewText,
                isEnabled: model.askEnabled,
                colors: colors
            ) {
                model.action?(.ask)
            }
            .frame(height: AIPanelChromeLayout.askHeight)
            .accessibilityIdentifier(AIPanelChromeButton.ask.accessibilityIdentifier)

            HStack(spacing: AIPanelChromeLayout.actionSpacing) {
                action(.summarize, title: AppText.localized("总结", "Summarize"), tooltip: nil)
                    .disabled(!model.contentActionsEnabled)
                    .opacity(model.contentActionsEnabled ? 1 : 0.5)
                action(.translate, title: AppText.localized("翻译", "Translate"), tooltip: nil)
                    .disabled(!model.contentActionsEnabled)
                    .opacity(model.contentActionsEnabled ? 1 : 0.5)
                action(
                    .export,
                    title: AppText.localized("导出", "Export"),
                    tooltip: AppText.localized("导出当前 AI 对话为 Markdown", "Export current AI conversation as Markdown")
                )
            }
            .frame(height: AIPanelChromeLayout.actionHeight)
            .id(model.languageToken)
        }
        .padding(.top, AIPanelChromeLayout.topInset)
        .padding(.horizontal, AIPanelChromeLayout.horizontalInset)
    }

    /// One of the three equal-width capsules.
    private func action(_ button: AIPanelChromeButton, title: String, tooltip: String?) -> some View {
        ChromeCapsuleButton(title: title, symbol: nil, palette: palette) {
            model.action?(button)
        }
        .frame(maxWidth: .infinity)
        .help(tooltip ?? "")
        .accessibilityIdentifier(button.accessibilityIdentifier)
    }
}

/// The AI panel's status row: animated dots, the status message, and the
/// cancel button. The dots and cancel appear only while a request is running.
struct AIPanelStatusView: View {
    @Bindable var model: AIPanelChromeModel

    private var colors: AIPanelColors { AIPanelColors(theme: model.theme) }

    var body: some View {
        HStack(spacing: 8) {
            // Reserving the slot keeps the status text from shifting sideways
            // when a request starts, which the fixed-width AppKit dots did too.
            Group {
                if model.isBusy {
                    AIPanelLoadingDots(color: Color(nsColor: colors.accent))
                }
            }
            .frame(width: AIPanelChromeLayout.dotsWidth, height: 10)

            Text(model.statusText)
                .font(.system(size: 14))
                .foregroundStyle(Color(nsColor: colors.secondaryText))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            if model.isBusy {
                Button {
                    model.action?(.cancelRequest)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(nsColor: colors.secondaryText))
                        .frame(width: AIPanelChromeLayout.cancelSize, height: AIPanelChromeLayout.cancelSize)
                }
                .buttonStyle(.plain)
                .help(AppText.cancel)
                .accessibilityIdentifier(AIPanelChromeButton.cancelRequest.accessibilityIdentifier)
            }
        }
        .frame(height: AIPanelChromeLayout.statusHeight)
    }
}

/// The gradient "ask" button: a title plus a truncating echo of the current
/// selection. Replaces `GradientButton`'s hand-drawn `draw(_:)`.
struct AIPanelAskButton: View {
    let previewText: String
    let isEnabled: Bool
    let colors: AIPanelColors
    let action: () -> Void

    /// The selection collapsed to one line, as the AppKit button drew it.
    private var preview: String {
        previewText
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(AppText.askAI)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isEnabled ? Color.white : Color(nsColor: colors.askDisabledText))
                    .fixedSize()
                if !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.86))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 18)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background { fill.clipShape(RoundedRectangle(cornerRadius: 18)) }
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        Color(nsColor: isEnabled ? colors.askEnabledStroke : colors.askDisabledStroke),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .shadow(color: isEnabled ? Color(nsColor: colors.accent).opacity(0.24) : .clear, radius: 4.5, y: 3)
    }

    @ViewBuilder
    private var fill: some View {
        if isEnabled {
            LinearGradient(
                colors: colors.askGradient.map { Color(nsColor: $0) },
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            Color(nsColor: colors.askDisabledFill)
        }
    }
}

/// Three dots cycling at the same 0.22 s cadence `LoadingDotsView` used. The
/// timer lives with the view, so it starts and stops with the busy state that
/// puts the view on screen.
struct AIPanelLoadingDots: View {
    let color: Color

    @State private var phase = 0
    private let tick = Timer.publish(every: 0.22, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color.opacity(index == phase ? 0.95 : 0.28))
                    .frame(width: 6, height: 6)
            }
        }
        .onReceive(tick) { _ in
            phase = (phase + 1) % 3
        }
    }
}

/// Theme-keyed colours for the AI panel, in one place so the AppKit panel and
/// the SwiftUI chrome read the same values. `AIChatPanel`'s colour properties
/// forward here rather than repeating the literals.
struct AIPanelColors {
    let theme: ReaderTheme

    init(theme: ReaderTheme) {
        self.theme = theme
    }

    var panelBackground: NSColor {
        switch theme {
        case .original: return NSColor.white.withAlphaComponent(0.97)
        case .eyeCare: return NSColor(red: 0.86, green: 0.82, blue: 0.68, alpha: 0.97)
        case .dark: return NSColor(red: 0.07, green: 0.09, blue: 0.11, alpha: 0.96)
        }
    }

    var primaryText: NSColor {
        switch theme {
        case .original: return NSColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1)
        case .eyeCare: return NSColor(red: 0.18, green: 0.15, blue: 0.09, alpha: 1)
        case .dark: return NSColor(red: 0.78, green: 0.81, blue: 0.86, alpha: 1)
        }
    }

    var secondaryText: NSColor {
        switch theme {
        case .original: return NSColor(red: 0.42, green: 0.44, blue: 0.49, alpha: 1)
        case .eyeCare: return NSColor(red: 0.45, green: 0.39, blue: 0.26, alpha: 1)
        case .dark: return NSColor(red: 0.55, green: 0.60, blue: 0.68, alpha: 1)
        }
    }

    var inputBackground: NSColor {
        switch theme {
        case .original: return NSColor(red: 0.93, green: 0.94, blue: 0.95, alpha: 1)
        case .eyeCare: return NSColor(red: 0.91, green: 0.86, blue: 0.70, alpha: 1)
        case .dark: return NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
        }
    }

    var inputBorder: NSColor {
        switch theme {
        case .original: return .clear
        case .eyeCare: return NSColor(red: 0.66, green: 0.60, blue: 0.43, alpha: 1)
        case .dark: return NSColor(red: 0.22, green: 0.26, blue: 0.32, alpha: 1)
        }
    }

    var accent: NSColor {
        switch theme {
        case .original: return NSColor(red: 0.0, green: 0.35, blue: 0.9, alpha: 1)
        case .eyeCare: return NSColor(red: 0.53, green: 0.37, blue: 0.14, alpha: 1)
        case .dark: return NSColor(red: 0.32, green: 0.55, blue: 1, alpha: 1)
        }
    }

    var askGradient: [NSColor] {
        switch theme {
        case .original:
            return [
                NSColor(red: 0.45, green: 0.18, blue: 0.96, alpha: 1),
                NSColor(red: 0.21, green: 0.50, blue: 0.98, alpha: 1)
            ]
        case .eyeCare:
            return [
                NSColor(red: 0.66, green: 0.43, blue: 0.13, alpha: 1),
                NSColor(red: 0.40, green: 0.53, blue: 0.24, alpha: 1)
            ]
        case .dark:
            return [
                NSColor(red: 0.34, green: 0.24, blue: 0.78, alpha: 1),
                NSColor(red: 0.16, green: 0.42, blue: 0.84, alpha: 1)
            ]
        }
    }

    var askEnabledStroke: NSColor {
        switch theme {
        case .original: return NSColor(red: 0.25, green: 0.33, blue: 0.92, alpha: 0.24)
        case .eyeCare: return NSColor(red: 0.46, green: 0.33, blue: 0.14, alpha: 0.30)
        case .dark: return NSColor(red: 0.24, green: 0.36, blue: 0.88, alpha: 0.30)
        }
    }

    var askDisabledFill: NSColor {
        switch theme {
        case .original: return NSColor(red: 0.93, green: 0.94, blue: 0.95, alpha: 1)
        case .eyeCare: return NSColor(red: 0.86, green: 0.81, blue: 0.66, alpha: 1)
        case .dark: return NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
        }
    }

    var askDisabledStroke: NSColor {
        switch theme {
        case .original: return NSColor(red: 0.88, green: 0.89, blue: 0.92, alpha: 1)
        case .eyeCare: return NSColor(red: 0.70, green: 0.64, blue: 0.46, alpha: 1)
        case .dark: return NSColor(red: 0.22, green: 0.26, blue: 0.32, alpha: 1)
        }
    }

    var askDisabledText: NSColor {
        switch theme {
        case .original: return NSColor(red: 0.70, green: 0.71, blue: 0.76, alpha: 1)
        case .eyeCare: return NSColor(red: 0.54, green: 0.47, blue: 0.30, alpha: 1)
        case .dark: return NSColor(red: 0.45, green: 0.49, blue: 0.55, alpha: 1)
        }
    }
}
