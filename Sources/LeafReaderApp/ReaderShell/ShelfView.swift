import SwiftUI

/// The shelf of recently opened documents.
///
/// Hosted inside the existing borderless panel, which keeps owning the window
/// and — importantly — the file-drop target, since drag-and-drop of documents
/// already works through `RecentDocumentsDropContentView` and is not worth
/// re-implementing.
struct ShelfView: View {
    @Bindable var model: ShelfModel

    private var palette: ShelfPalette { ShelfPalette(theme: model.theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .background(palette.background)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(palette.primaryText)
            Text(AppText.localized("书架", "Shelf"))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.primaryText)
            Spacer(minLength: 16)
            actionButton(AppText.localized("增加", "Add"), isPrimary: true) { model.onAdd?() }
                .accessibilityIdentifier(ShelfAccessibility.addButton)
            actionButton(AppText.localized("清空", "Clear"), isPrimary: false) { model.onClearAll?() }
                .accessibilityIdentifier(ShelfAccessibility.clearButton)
            Button {
                model.onClose?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(ShelfAccessibility.closeButton)
            .accessibilityLabel(AppText.close)
        }
        .padding(.top, 32)
        .padding(.horizontal, 34)
    }

    @ViewBuilder
    private var content: some View {
        if model.isEmpty {
            // The shelf accepts dropped files, so an empty one should say so
            // rather than look broken.
            Text(AppText.localized(
                "书架是空的。拖入文件或点击“增加”。",
                "The shelf is empty. Drop a document here or click Add."
            ))
            .font(.system(size: 14))
            .foregroundStyle(palette.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 36)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 28) {
                        ForEach(model.items, id: \.path) { item in
                            ShelfCard(item: item, model: model, palette: palette)
                                .id(item.path)
                        }
                    }
                    .padding(.trailing, 10)
                    .padding(.vertical, 2)
                }
                .scrollContentBackground(.hidden)
                .onAppear {
                    // Opened right after an import: show the file just added.
                    guard let focus = model.focusPath else { return }
                    proxy.scrollTo(focus, anchor: .center)
                }
            }
            .padding(.top, 38)
            .padding(.horizontal, 36)
            .padding(.bottom, 42)
        }
    }

    private func actionButton(
        _ title: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minWidth: 104, minHeight: 44)
                .foregroundStyle(isPrimary ? palette.primaryActionText : palette.primaryText)
                .background(
                    isPrimary ? palette.accent : palette.secondaryButtonBackground,
                    in: RoundedRectangle(cornerRadius: 10)
                )
                // The secondary button's fill is near-white on the light theme,
                // so without the border it reads as plain text rather than a
                // button — the AppKit original stroked it for this reason.
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isPrimary ? .clear : palette.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// One document on the shelf.
private struct ShelfCard: View {
    let item: RecentDocumentItem
    let model: ShelfModel
    let palette: ShelfPalette

    private var cover: PlatformImage {
        model.covers.cachedCover(for: item)
            ?? model.covers.placeholder(
                title: item.title,
                kind: item.kind,
                isDark: model.theme == .dark
            )
    }

    var body: some View {
        // A real Button rather than a tap gesture: a gesture is invisible to
        // accessibility, so the card had no default action and pressing it did
        // nothing for anyone not using a pointer.
        Button {
            model.onOpen?(item.path)
        } label: {
            cardBody
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(ShelfAccessibility.card)
        .accessibilityLabel(item.title)
        .onAppear { model.covers.loadCover(for: item) }
        .contextMenu {
            Button(AppText.localized("打开", "Open")) { model.onOpen?(item.path) }
            Button(AppText.localized("在 Finder 中显示", "Show in Finder")) { model.onReveal?(item.path) }
            Divider()
            // Every item below deletes something. They route out to the panel,
            // which confirms before anything happens.
            Button(AppText.localized("移出书架", "Remove from Shelf")) { model.onRemove?(item.path) }
            Button(AppText.localized("清除本书 AI 分析缓存", "Clear Book AI Analysis Cache")) {
                model.onClearVectorCache?(item.path)
            }
            Button(AppText.localized("清除本书单词记录", "Clear Book Words")) {
                model.onClearWordRecords?(item.path)
            }
            Button(AppText.localized("清除本书 AI 数据", "Clear Book AI Data")) {
                model.onClearAIData?(item.path)
            }
        }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(platformImage: cover)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(
                    width: ShelfCoverLoader.coverSize.width,
                    height: ShelfCoverLoader.coverSize.height
                )
                .background(palette.coverBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(palette.coverBorder, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(palette.coverShadowOpacity), radius: 9, y: 4)

            Text(item.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
                .padding(.top, 12)

            Text(ShelfCardPresenter.documentKindText(item.kind))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .padding(.top, 6)

            Text(ShelfCardPresenter.progressText(readingProgress: item.readingProgress))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.secondaryText.opacity(0.92))
                .lineLimit(1)
                .padding(.top, 5)
        }
        .frame(width: ShelfCoverLoader.coverSize.width, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// The shelf's colours as SwiftUI values.
///
/// Built entirely from `ShelfColorTokens` (platform-neutral `DesignColor`s), so
/// this — and the whole `ShelfView` colour path — has no `NSColor` dependency
/// and compiles on iOS. It is the first migrated screen whose colours are
/// portable rather than merely rendered in SwiftUI.
struct ShelfPalette {
    let background: Color
    let primaryText: Color
    let secondaryText: Color
    let accent: Color
    let secondaryButtonBackground: Color
    let border: Color
    let primaryActionText: Color
    let coverBackground: Color
    let coverBorder: Color
    let coverShadowOpacity: Double

    init(theme: ReaderTheme) {
        let isDark = theme == .dark
        let tokens = theme.shelfColorTokens
        background = tokens.background.color
        primaryText = tokens.primaryText.color
        secondaryText = tokens.secondaryText.color
        accent = tokens.accent.color
        secondaryButtonBackground = tokens.secondaryButtonBackground.color
        border = tokens.border.color
        primaryActionText = tokens.primaryActionText.color
        coverBackground = isDark
            ? Color(red: 0.14, green: 0.16, blue: 0.20)
            : Color(red: 0.98, green: 0.98, blue: 0.985)
        coverBorder = .black.opacity(isDark ? 0.35 : 0.08)
        coverShadowOpacity = isDark ? 0.32 : 0.20
    }
}
