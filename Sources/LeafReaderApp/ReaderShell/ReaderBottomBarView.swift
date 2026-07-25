import SwiftUI

/// State behind the reader's bottom bar.
///
/// The bar is core reading chrome, so this is deliberately thin: it holds the
/// theme, a language-change token (SwiftUI reads `AppText` live, but needs a
/// nudge to re-render when the interface language changes), the transient
/// AI-analysis state, and the actions each control fires. Which controls exist
/// and in what order is `ReaderBottomBarLayout`.
@Observable
final class ReaderBottomBarModel {
    var theme: ReaderTheme = ReaderTheme.selected
    /// Bumped when the interface language changes, to force a re-render.
    var languageToken: Int = 0

    // Transient AI-analysis cluster, pushed from the embedding coordinator.
    var embeddingStatusText: String = ""
    var embeddingStatusVisible: Bool = false
    var embeddingControlsVisible: Bool = false
    var embeddingPaused: Bool = false

    /// The TOC button's frame in the bar's coordinate space, reported by the
    /// view so the AppKit table-of-contents menu still pops up beneath it.
    var tocButtonFrame: CGRect = .zero

    @ObservationIgnored var action: ((ReaderBottomBarItem.Identifier) -> Void)?
}

/// The reader's bottom bar, declarative SwiftUI.
///
/// Replaces a row of custom-drawn `CapsuleChromeButton`s positioned by hand in
/// `ReaderWindowController+UILayout`. Three groups, matching the original: the
/// settings gear and panel buttons pinned leading, the page-navigation group
/// centred, and the AI-analysis controls trailing (shown only while an analysis
/// runs). PDFKit/WebKit and the document itself are untouched — this is only the
/// chrome.
struct ReaderBottomBarView: View {
    @Bindable var model: ReaderBottomBarModel

    private var palette: ChromeCapsulePalette { ChromeCapsulePalette(theme: model.theme) }

    var body: some View {
        ZStack {
            leadingCluster.frame(maxWidth: .infinity, alignment: .leading)
            navigationCluster
                .frame(maxWidth: .infinity, alignment: .center)
                .offset(x: ReaderUILayout.navigationStackCenterOffset)
            if model.embeddingStatusVisible || model.embeddingControlsVisible {
                embeddingCluster.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: Self.coordinateSpace)
        // Depend on the language token so a language change re-renders the
        // AppText-derived titles.
        .id(model.languageToken)
    }

    static let coordinateSpace = "readerBottomBar"

    private var leadingCluster: some View {
        HStack(spacing: 0) {
            Button { model.action?(.settings) } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 19))
                    .foregroundStyle(palette.iconTint)
                    .frame(width: ReaderUILayout.settingsButtonSize, height: ReaderUILayout.settingsButtonSize)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(ReaderBottomBarItem.Identifier.settings.accessibilityIdentifier)
            .accessibilityLabel(AppText.settings)
            .padding(.leading, ReaderUILayout.settingsLeading)

            ForEach(ReaderBottomBarLayout.items(in: .panels), id: \.id) { item in
                capsule(item)
                    .padding(.leading, panelLeading(item.id))
            }
        }
    }

    private var navigationCluster: some View {
        HStack(spacing: ReaderUILayout.navigationStackSpacing) {
            ForEach(ReaderBottomBarLayout.items(in: .navigation), id: \.id) { item in
                if item.id == .toc {
                    capsule(item).background(tocFrameReporter)
                } else {
                    capsule(item)
                }
            }
        }
    }

    private var embeddingCluster: some View {
        HStack(spacing: 8) {
            if model.embeddingStatusVisible {
                Text(model.embeddingStatusText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.iconTint)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: ReaderUILayout.embeddingStatusMaxWidth, alignment: .trailing)
            }
            if model.embeddingControlsVisible {
                capsule(.embeddingPause, titleOverride: model.embeddingPaused
                    ? AppText.localized("继续", "Resume")
                    : AppText.localized("暂停", "Pause"))
                capsule(.embeddingCancel)
            }
        }
        .padding(.trailing, 18)
    }

    /// Reports the TOC button's frame so the AppKit menu still anchors to it.
    private var tocFrameReporter: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { model.tocButtonFrame = geo.frame(in: .named(Self.coordinateSpace)) }
                .onChange(of: geo.frame(in: .named(Self.coordinateSpace))) { _, frame in
                    model.tocButtonFrame = frame
                }
        }
    }

    private func capsule(_ id: ReaderBottomBarItem.Identifier, titleOverride: String? = nil) -> some View {
        let item = ReaderBottomBarLayout.items.first { $0.id == id }
        return ChromeCapsuleButton(
            title: titleOverride ?? ReaderBottomBarTitles.title(for: id),
            symbol: item?.showsLeadingSymbol == true ? ReaderBottomBarTitles.symbol(for: id) : nil,
            palette: palette
        ) {
            model.action?(id)
        }
        .frame(width: capsuleWidth(id), height: ReaderUILayout.bottomButtonHeight)
        .accessibilityIdentifier(id.accessibilityIdentifier)
    }

    private func capsule(_ item: ReaderBottomBarItem) -> some View { capsule(item.id) }

    private func panelLeading(_ id: ReaderBottomBarItem.Identifier) -> CGFloat {
        switch id {
        case .shelf: return ReaderUILayout.shelfButtonLeading
        case .words: return ReaderUILayout.vocabularyLibraryButtonLeading
        case .review: return ReaderUILayout.vocabularyButtonLeading
        case .notes: return ReaderUILayout.notesButtonLeading
        default: return 0
        }
    }

    private func capsuleWidth(_ id: ReaderBottomBarItem.Identifier) -> CGFloat {
        switch id {
        case .shelf: return ReaderUILayout.shelfButtonWidth
        case .words: return ReaderUILayout.vocabularyLibraryButtonWidth
        case .review: return ReaderUILayout.vocabularyButtonWidth
        case .notes: return ReaderUILayout.notesButtonWidth
        case .toc: return ReaderUILayout.tocButtonWidth
        case .cover: return ReaderUILayout.coverButtonWidth
        case .previousPage, .nextPage: return ReaderUILayout.readerNavButtonWidth
        case .farthestPosition: return ReaderUILayout.farthestPositionButtonWidth
        case .embeddingPause, .embeddingCancel: return ReaderUILayout.embeddingButtonWidth
        case .settings: return ReaderUILayout.settingsButtonSize
        }
    }
}

/// Titles, symbols and tooltips for bottom-bar controls, in one place so the
/// SwiftUI view and any future consumer read the same strings.
enum ReaderBottomBarTitles {
    static func title(for id: ReaderBottomBarItem.Identifier) -> String {
        switch id {
        case .settings: return ""
        case .shelf: return AppText.localized("书架", "Shelf")
        case .words: return AppText.localized("生词", "Words")
        case .notes: return AppText.localized("笔记", "Notes")
        case .review: return AppText.localized("背单词", "Review")
        case .toc: return AppText.localized("目录", "TOC")
        case .cover: return AppText.cover
        case .previousPage: return AppText.prev
        case .nextPage: return AppText.next
        case .farthestPosition: return AppText.localized("上次位置", "Last")
        case .embeddingPause: return AppText.localized("暂停", "Pause")
        case .embeddingCancel: return AppText.localized("取消", "Cancel")
        }
    }

    static func symbol(for id: ReaderBottomBarItem.Identifier) -> String {
        switch id {
        case .settings: return "gearshape"
        case .shelf: return "books.vertical"
        case .words: return "text.word.spacing"
        case .notes: return "note.text"
        case .review: return "text.book.closed"
        case .toc: return "list.bullet"
        case .cover: return "book.closed"
        case .previousPage: return "chevron.left"
        case .nextPage: return "chevron.right"
        case .farthestPosition: return "arrow.turn.down.right"
        case .embeddingPause: return "pause.fill"
        case .embeddingCancel: return "xmark"
        }
    }
}
