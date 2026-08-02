import SwiftUI
import LeafReaderCore

/// State behind the reader's top toolbar.
///
/// Like `ReaderBottomBarModel`, this stays thin. It carries the theme, a
/// language-change token, the chrome-state visibility flags, and the small
/// amount of control state the toolbar's native buttons render from
/// (read-aloud phase and page-layout/crop mode). Everything that is
/// *content* — the document title and cover image — stays on the existing
/// AppKit instances the view bridges in, for their verified window-drag
/// behaviour. Page and zoom fields remain AppKit editing adapters, but their
/// displayed values are projections of focused reader state. The title label is now a
/// *reflection* of `ReaderPresentationState.documentTitle` rather than the
/// source of truth: AI context, embedding, and read-aloud read the model
/// (`documentTitle`), so read-aloud can overwrite the label with progress text
/// without corrupting what those consumers see. The editable fields keep their
/// AppKit behaviour untouched; SwiftUI owns only their placement.
@Observable
final class ReaderTopBarModel {
    var theme: ReaderTheme = ReaderTheme.selected
    /// Bumped when the interface language changes, to force the AppText-derived
    /// button titles to re-render.
    var languageToken: Int = 0

    // Chrome-state visibility, mirroring `ReaderChromeState`.
    var showsCover: Bool = false
    var showsRelatedFormsToggle: Bool = false
    var showsPageLayoutButton: Bool = false
    var showsCropButton: Bool = false
    var showsReadAloudStopButton: Bool = false

    // Native-control state.
    var relatedFormsOn: Bool = true
    var readAloudActive: Bool = false
    var readAloudPaused: Bool = false
    var readAloudLoading: Bool = false
    var pageLayoutIsTwoPage: Bool = false
    var pageLayoutEnabled: Bool = true
    var cropIsEnabled: Bool = false

    @ObservationIgnored var action: ((ReaderTopBarButton) -> Void)?
    /// Called only when the user flips the related-forms switch, never when the
    /// value is synced programmatically from the chrome state.
    @ObservationIgnored var onRelatedFormsChanged: ((Bool) -> Void)?
}

/// The top toolbar's tappable native buttons.
enum ReaderTopBarButton {
    case readAloud
    case readAloudStop
    case pageLayout
    case crop
}

/// The reader's top toolbar, declarative SwiftUI.
///
/// Replaces the hand-placed constraints in `ReaderWindowController+UILayout` for
/// the buttons: native SwiftUI renders the read-aloud/page-layout/crop
/// capsules and the related-forms toggle, and bridges the (non-editable) title and
/// cover so window-drag and the title-as-data reads stay intact.
///
/// The centre cluster — the editable zoom group, the editable page field and the
/// search controls — is deliberately **not** here. Editable `NSTextField`s do not
/// receive first-responder for editing when hosted inside an `NSHostingView`, so
/// those stay AppKit, positioned by constraints and layered on top of this view
/// (see `configureToolbarViews`). This view only fills the two edge regions and
/// leaves the centre empty for them.
struct ReaderTopBarView: View {
    @Bindable var model: ReaderTopBarModel

    // Existing (non-editable) AppKit instances, bridged in (not re-created).
    let title: NSView
    let cover: NSView

    private var palette: ChromeCapsulePalette { ChromeCapsulePalette(theme: model.theme) }

    /// The right edge of the before-zoom cluster: just left of the zoom group.
    private var beforeZoomRightOffset: CGFloat {
        ReaderUILayout.zoomCenterOffset - ReaderUILayout.zoomGroupSize.width / 2 - ReaderToolbarLayout.beforeZoomGap
    }

    /// The AppKit search icon's right edge, relative to the window centre (the
    /// centre cluster is AppKit, positioned by these same constants).
    private var searchRightEdgeOffset: CGFloat {
        ReaderUILayout.pageLabelCenterOffset + ReaderUILayout.pageLabelWidth / 2
            + ReaderUILayout.searchUnderlineLeading + ReaderUILayout.searchUnderlineSize.width
            + ReaderUILayout.searchButtonLeading + ReaderUILayout.iconButtonSize
    }

    /// Natural width of the visible trailing capsules (page-layout and crop are
    /// hidden for non-PDF documents).
    private var trailingWidth: CGFloat {
        var width: CGFloat = 0
        if model.showsPageLayoutButton {
            width += ReaderUILayout.pageLayoutButtonWidth
        }
        if model.showsCropButton {
            if width > 0 { width += ReaderToolbarLayout.clusterSpacing }
            width += ReaderUILayout.cropButtonWidth
        }
        return width
    }

    /// The trailing cluster's leading x. Pinned to the trailing edge when there
    /// is room, but never allowed to slide under the search icon — instead it
    /// flows off the right edge, exactly as the AppKit constraint
    /// `trailingStack.leading >= searchButton.trailing + spacing` did. This is
    /// what keeps the centre-anchored search and the edge-pinned buttons from
    /// overlapping as the window narrows.
    private func trailingLeadingX(center: CGFloat, width: CGFloat) -> CGFloat {
        let rightPinned = width - ReaderToolbarLayout.trailingInset - trailingWidth
        let minLeading = center + searchRightEdgeOffset + ReaderToolbarLayout.clusterSpacing
        return max(rightPinned, minLeading)
    }

    var body: some View {
        GeometryReader { geo in
            let center = geo.size.width / 2
            ZStack {
                // The leading edge up to just before the zoom group: cover, title
                // (truncating), a flexible gap, then the before-zoom controls. A
                // single HStack means the title compresses instead of overlapping
                // the controls — the behaviour the AppKit constraints enforced.
                leftRegion
                    .frame(width: max(0, center + beforeZoomRightOffset - ReaderToolbarLayout.leadingInset), alignment: .leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.leading, ReaderToolbarLayout.leadingInset)

                // Centre (zoom group, page field, search) is an AppKit overlay,
                // layered on top of this hosting view — see the type doc.

                trailingCluster
                    .id(model.languageToken)
                    .frame(width: trailingWidth, height: geo.size.height)
                    .position(
                        x: trailingLeadingX(center: center, width: geo.size.width) + trailingWidth / 2,
                        y: geo.size.height / 2
                    )
            }
            .clipped()
        }
        // No accessibility modifier on the root: it would collapse the bar into a
        // single element and hide the buttons. The findable container identifier
        // lives on the hosting NSView instead (see `configureToolbarViews`).
    }

    /// Identifier set on the toolbar NSView so the smoke test can reach the
    /// nested SwiftUI buttons without walking the PDF accessibility tree.
    static let accessibilityIdentifier = "readerTopBar"

    // MARK: - Clusters

    /// Cover thumbnail + truncating title + the before-zoom controls, laid out
    /// left-to-right so the title yields space (and truncates) rather than
    /// overlapping the controls. Cover and title bridge the AppKit instances so
    /// window-drag and the title-as-data reads stay intact.
    private var leftRegion: some View {
        HStack(spacing: 0) {
            if model.showsCover {
                ChromeViewBridge(view: cover)
                    .frame(width: ReaderUILayout.coverSize.width, height: ReaderUILayout.coverSize.height)
                    .padding(.trailing, ReaderToolbarLayout.titleClusterSpacing)
            }
            FlexibleTitleBridge(view: title)
                .frame(maxWidth: ReaderUILayout.titleMaxWidth, alignment: .leading)
            Spacer(minLength: ReaderUILayout.titleToReadAloudMinimum)
            beforeZoomCluster
                .id(model.languageToken)
                .layoutPriority(1)
        }
    }

    /// Related-forms toggle + read-aloud controls, anchored just left of the
    /// centred zoom group.
    private var beforeZoomCluster: some View {
        HStack(spacing: ReaderToolbarLayout.clusterSpacing) {
            if model.showsRelatedFormsToggle {
                relatedFormsToggle
            }
            readAloudButton
            if model.showsReadAloudStopButton {
                capsule(
                    .readAloudStop,
                    title: AppText.localized("停止", "Stop"),
                    symbol: "stop.fill",
                    tooltip: AppText.localized("停止朗读", "Stop reading"),
                    width: ReaderUILayout.readAloudStopButtonWidth
                )
            }
        }
    }

    /// Page-layout and crop capsules, pinned trailing.
    private var trailingCluster: some View {
        HStack(spacing: ReaderToolbarLayout.clusterSpacing) {
            if model.showsPageLayoutButton {
                let text = ReaderTopBarTitles.pageLayout(isTwoPage: model.pageLayoutIsTwoPage)
                capsule(.pageLayout, title: text.title, symbol: nil, tooltip: text.tooltip,
                        width: ReaderUILayout.pageLayoutButtonWidth)
                    .disabled(!model.pageLayoutEnabled)
                    .opacity(model.pageLayoutEnabled ? 1 : 0.5)
            }
            if model.showsCropButton {
                let text = ReaderTopBarTitles.crop(isEnabled: model.cropIsEnabled)
                capsule(.crop, title: text.title, symbol: nil, tooltip: text.tooltip,
                        width: ReaderUILayout.cropButtonWidth)
            }
        }
    }

    private var readAloudButton: some View {
        let text = ReaderTopBarTitles.readAloud(
            active: model.readAloudActive,
            paused: model.readAloudPaused,
            loading: model.readAloudLoading
        )
        return capsule(.readAloud, title: text.title, symbol: text.symbol, tooltip: text.tooltip,
                       width: ReaderUILayout.readAloudButtonWidth)
            .disabled(model.readAloudLoading)
    }

    private var relatedFormsToggle: some View {
        HStack(spacing: 5) {
            Image(systemName: "highlighter")
                .font(.system(size: 13))
                .foregroundStyle(palette.iconTint)
            Toggle("", isOn: Binding(
                get: { model.relatedFormsOn },
                set: { model.relatedFormsOn = $0; model.onRelatedFormsChanged?($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .help(AppText.localized("显示相关词形的蓝色标注", "Show blue markings for related word forms"))
        .accessibilityIdentifier("topBar.relatedForms")
    }

    private func capsule(
        _ button: ReaderTopBarButton,
        title: String,
        symbol: String?,
        tooltip: String?,
        width: CGFloat
    ) -> some View {
        ChromeCapsuleButton(title: title, symbol: symbol, palette: palette) {
            model.action?(button)
        }
        .frame(width: width, height: ReaderUILayout.toolbarButtonHeight)
        .help(tooltip ?? "")
        .accessibilityIdentifier(button.accessibilityIdentifier)
    }
}

extension ReaderTopBarButton {
    var accessibilityIdentifier: String {
        switch self {
        case .readAloud: return "topBar.readAloud"
        case .readAloudStop: return "topBar.readAloudStop"
        case .pageLayout: return "topBar.pageLayout"
        case .crop: return "topBar.crop"
        }
    }
}

/// Bridges an existing AppKit control into the SwiftUI layout without
/// re-creating it, so its editing, window-drag and custom drawing behaviour are
/// preserved exactly. SwiftUI owns only where it sits; the instance keeps its
/// target/action, delegate and theming (reached by the chrome theme walk).
struct ChromeViewBridge: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
    /// Report the size SwiftUI proposes (from the `.frame` modifiers), so the
    /// embedded NSView is *sized to* its frame rather than rendering at its
    /// intrinsic size and overflowing — e.g. the 56×76 cover image clamped to
    /// the 28×38 slot.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        let intrinsic = nsView.intrinsicContentSize
        let width = proposal.width.flatMap { $0 == .infinity ? nil : $0 } ?? intrinsic.width
        let height = proposal.height.flatMap { $0 == .infinity ? nil : $0 } ?? intrinsic.height
        return CGSize(width: width, height: height)
    }
}

/// Like `ChromeViewBridge` but width-flexible: it reports a size no wider than
/// its natural width yet accepts a narrower proposal, so the bridged title label
/// truncates (its `.byTruncatingTail`) when the window is narrow instead of
/// overflowing into the neighbouring controls.
struct FlexibleTitleBridge: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        let intrinsic = nsView.intrinsicContentSize
        let width: CGFloat
        if let proposed = proposal.width, proposed != .infinity {
            width = min(proposed, intrinsic.width)
        } else {
            width = intrinsic.width
        }
        return CGSize(width: width, height: intrinsic.height)
    }
}

/// Titles, symbols and tooltips for the top bar's stateful native controls, in
/// one place, mirroring the strings the AppKit updaters used to set.
enum ReaderTopBarTitles {
    static func readAloud(active: Bool, paused: Bool, loading: Bool) -> (title: String, symbol: String, tooltip: String) {
        if loading {
            return (AppText.localized("加载中", "Loading"), "hourglass",
                    AppText.localized("正在加载朗读模型", "Loading read aloud model"))
        }
        if paused {
            return (AppText.localized("继续", "Resume"), "play.fill",
                    AppText.localized("继续朗读", "Resume reading"))
        }
        if active {
            return (AppText.localized("暂停", "Pause"), "pause.fill",
                    AppText.localized("暂停朗读", "Pause reading"))
        }
        return (AppText.localized("朗读", "Read"), "speaker.wave.2",
                AppText.localized("从当前屏幕顶部开始朗读", "Read from the top of the current screen"))
    }

    static func pageLayout(isTwoPage: Bool) -> (title: String, tooltip: String) {
        isTwoPage
            ? (AppText.localized("单页", "Single"), AppText.localized("切换到单页浏览", "Switch to single-page view"))
            : (AppText.localized("双页", "Two-up"), AppText.localized("切换到双页浏览", "Switch to two-page view"))
    }

    static func crop(isEnabled: Bool) -> (title: String, tooltip: String) {
        isEnabled
            ? (AppText.localized("原边", "Original"), AppText.localized("恢复 PDF 原始页面边距", "Restore original PDF page margins"))
            : (AppText.localized("裁边", "Crop"), AppText.localized("裁掉 PDF 页面外侧空白", "Crop outer PDF margins"))
    }

}
