import SwiftUI

/// The Reading Notes list.
///
/// Hosted inside the existing borderless panel, which keeps owning the window
/// shell — placement, rounded corners and shadow. This view owns everything
/// inside it, replacing the hand-built `NSStackView` of `ReadingNoteRowView`s
/// that had to be torn down and rebuilt on every keystroke and theme change.
struct ReadingNotesListView: View {
    @Bindable var model: ReadingNotesListModel
    @FocusState private var searchFocused: Bool

    private var palette: ReadingNotePalette { ReadingNotePalette(theme: model.theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            search
            Text(model.summaryText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.secondaryText)
                .padding(.top, 10)
                .padding(.horizontal, 34)
                .accessibilityIdentifier(ReadingNotesAccessibility.summaryLabel)
            list
        }
        .background(palette.panelBackground)
        .onAppear { searchFocused = true }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(palette.accent)
            Text(AppText.localized("阅读笔记", "Reading Notes"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(palette.primaryText)
            Spacer(minLength: 18)
            actionButton(AppText.localized("导出笔记", "Export Notes"), role: .primary) {
                model.onExport?()
            }
            .accessibilityIdentifier(ReadingNotesAccessibility.exportButton)
            actionButton(AppText.close, role: .secondary) {
                model.onClose?()
            }
            .accessibilityIdentifier(ReadingNotesAccessibility.closeButton)
        }
        .padding(.top, 34)
        .padding(.horizontal, 34)
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.secondaryText)
            TextField(
                AppText.localized("搜索笔记", "Search notes"),
                text: $model.searchQuery
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.primaryText)
            .focused($searchFocused)
            .accessibilityIdentifier(ReadingNotesAccessibility.searchField)
            .accessibilityLabel(AppText.localized("搜索笔记", "Search notes"))
            if !model.searchQuery.isEmpty {
                Button {
                    model.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppText.localized("清除搜索", "Clear search"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(palette.insetBackground, in: RoundedRectangle(cornerRadius: 8))
        .padding(.top, 14)
        .padding(.horizontal, 34)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if model.rows.isEmpty {
                    Text(model.emptyStateText)
                        .font(.system(size: 15))
                        .foregroundStyle(palette.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                } else {
                    ForEach(model.rows, id: \.id) { row in
                        ReadingNoteRow(row: row, palette: palette) { action in
                            switch action {
                            case .open: model.open(rowID: row.id)
                            case .toggleFavorite: model.toggleFavorite(rowID: row.id)
                            case .delete: model.delete(rowID: row.id)
                            }
                        }
                    }
                }
            }
            .padding(.top, 2)
            .padding(.trailing, 12)
        }
        .scrollContentBackground(.hidden)
        .padding(.top, 12)
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
    }

    private enum ActionRole { case primary, secondary }

    private func actionButton(
        _ title: String,
        role: ActionRole,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            // Width is a floor, not a fixed size: the AppKit original pinned
            // these to 88pt, which "Export Notes" overflowed. Localised titles
            // vary in length, so let the label decide and keep 88 only so short
            // titles still read as buttons.
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minWidth: 88, minHeight: 32)
                .foregroundStyle(role == .primary ? palette.primaryActionText : palette.primaryText)
                .background(
                    role == .primary ? palette.accent : palette.secondaryButtonBackground,
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .buttonStyle(.plain)
    }
}

/// One note in the list.
private struct ReadingNoteRow: View {
    enum Action { case open, toggleFavorite, delete }

    let row: ReadingNoteListRowViewModel
    let palette: ReadingNotePalette
    let perform: (Action) -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.text")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 42, height: 42)
                .background(palette.insetBackground, in: RoundedRectangle(cornerRadius: 8))

            Text(row.locationText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.primaryText)
                .frame(width: 56, alignment: .leading)

            Text(row.titleText)
                .font(.system(size: 14))
                .foregroundStyle(palette.primaryText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Favourite and delete sit above the row-wide open tap target, so
            // they must come after it in z-order — hence the row background
            // carries the open gesture rather than wrapping the whole HStack in
            // a Button, which would swallow these.
            Button {
                perform(.toggleFavorite)
            } label: {
                Image(systemName: row.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(row.isFavorite ? palette.accent : palette.secondaryText)
                    .frame(width: 34, height: 32)
            }
            .buttonStyle(.plain)
            .help(row.isFavorite
                ? AppText.localized("取消收藏", "Remove favorite")
                : AppText.localized("收藏并置顶", "Favorite and pin"))
            .accessibilityIdentifier(ReadingNotesAccessibility.favoriteButton)
            // The label states the action, not the icon: a star that reads as
            // "star" tells a screen-reader user nothing about what it will do,
            // and the two states do opposite things.
            .accessibilityLabel(row.isFavorite
                ? AppText.localized("取消收藏", "Remove favorite")
                : AppText.localized("收藏并置顶", "Favorite and pin"))

            Button {
                perform(.delete)
            } label: {
                Text(AppText.localized("删除", "Delete"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)
                    .frame(width: 48, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(ReadingNotesAccessibility.deleteButton)
            .accessibilityLabel(AppText.localized("删除笔记", "Delete note"))
        }
        .padding(.horizontal, 16)
        .frame(height: 74)
        .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { perform(.open) }
        // The row opens on tap, but a tap gesture is invisible to assistive
        // tech — without an explicit action there is no way to open a note
        // except with a pointer.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ReadingNotesAccessibility.row)
        .accessibilityLabel("\(row.locationText), \(row.titleText)")
        .accessibilityAction(named: AppText.localized("打开笔记", "Open note")) { perform(.open) }
    }
}

/// The note panel's colours as SwiftUI values.
///
/// `ReadingNoteTheme` stays the single definition; this only converts, so the
/// AppKit note editor and this list cannot drift apart.
struct ReadingNotePalette {
    let panelBackground: Color
    let cardBackground: Color
    let insetBackground: Color
    let primaryText: Color
    let secondaryText: Color
    let accent: Color
    let secondaryButtonBackground: Color
    let primaryActionText: Color

    init(theme: ReaderTheme) {
        panelBackground = Color(nsColor: ReadingNoteTheme.panelBackground(theme))
        cardBackground = Color(nsColor: ReadingNoteTheme.cardBackground(theme))
        insetBackground = Color(nsColor: ReadingNoteTheme.insetBackground(theme))
        primaryText = Color(nsColor: ReadingNoteTheme.primaryText(theme))
        secondaryText = Color(nsColor: ReadingNoteTheme.secondaryText(theme))
        accent = Color(nsColor: ReadingNoteTheme.accent(theme))
        secondaryButtonBackground = Color(nsColor: ReadingNoteTheme.secondaryButtonBackground(theme))
        // Matches the AppKit primary button: white on the light themes, the
        // regular text colour on dark where white would glare.
        primaryActionText = theme == .dark
            ? Color(nsColor: ReadingNoteTheme.primaryText(theme))
            : .white
    }
}
