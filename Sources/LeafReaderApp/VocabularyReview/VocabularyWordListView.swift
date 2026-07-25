import SwiftUI

/// The trainer's list of saved words.
///
/// Replaces an `NSScrollView` + `NSStackView` filled by `populateVocabularyStack`,
/// where each row was built by `vocabularyCard` (≈175 lines of views and
/// constraints), its expanded occurrences by `vocabularyOccurrenceRow`, and the
/// pager by `vocabularyPaginationView` — all rebuilt from scratch on every
/// reload, including on every occurrence expand/collapse.
struct VocabularyWordListView: View {
    @Bindable var model: VocabularyWordListModel
    let theme: ReaderTheme

    private var palette: VocabularyCardPalette { VocabularyCardPalette(theme: theme) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if let emptyMessage = model.emptyMessage {
                    Text(emptyMessage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ForEach(model.rows) { row in
                        card(row)
                    }
                    if model.showsPagination {
                        pagination
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollContentBackground(.hidden)
    }

    private func card(_ row: VocabularyWordRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("•")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(palette.accent)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 10) {
                header(row)
                statusRow(row)
                if let answer = row.answer {
                    Text(answer)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !row.occurrences.isEmpty {
                    occurrences(row)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 28)
        .padding(.trailing, 18)
        .padding(.vertical, 16)
        .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.cardBorder, lineWidth: 1))
    }

    private func header(_ row: VocabularyWordRow) -> some View {
        HStack(spacing: 8) {
            Text(row.word)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
            if row.hasPronunciation {
                smallButton(systemImage: "speaker.wave.2.fill",
                            help: AppText.localized("播放单词发音", "Play word pronunciation")) {
                    model.action?(.speak(word: row.word))
                }
            }
            smallButton(title: AppText.localized("复制", "Copy"), width: 68) {
                model.action?(.copy(word: row.word))
            }
            Spacer(minLength: 8)
            Text(row.location)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
        }
    }

    private func statusRow(_ row: VocabularyWordRow) -> some View {
        HStack(spacing: 12) {
            Text(row.status)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
            smallButton(title: AppText.localized("删除", "Delete"), width: 72) {
                model.action?(.delete(recordIDs: row.recordIDs))
            }
            Spacer(minLength: 0)
        }
    }

    private func occurrences(_ row: VocabularyWordRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                model.action?(.toggleOccurrences(key: row.id))
            } label: {
                Text(row.disclosureTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
            }
            .buttonStyle(.plain)
            .background(palette.secondaryButton, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.cardBorder, lineWidth: 1))

            if row.isExpanded {
                ForEach(row.occurrences) { occurrence in
                    HStack(alignment: .top, spacing: 10) {
                        smallButton(title: occurrence.location, width: 82) {
                            model.action?(.openOccurrence(id: occurrence.id))
                        }
                        Text(occurrence.context)
                            .textSelection(.enabled)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .background(palette.cardBackground.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }

    private var pagination: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            smallButton(title: AppText.localized("上一页", "Previous"), width: 86) {
                model.action?(.previousPage)
            }
            .disabled(!model.canGoBack)
            .opacity(model.canGoBack ? 1 : 0.4)

            Text(model.pageLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.secondaryText)
                .frame(minWidth: 150)

            smallButton(title: AppText.localized("下一页", "Next"), width: 86) {
                model.action?(.nextPage)
            }
            .disabled(!model.canGoForward)
            .opacity(model.canGoForward ? 1 : 0.4)
            Spacer(minLength: 0)
        }
        .frame(height: 52)
    }

    private func smallButton(title: String, width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
                .frame(width: width, height: 26)
        }
        .buttonStyle(.plain)
        .background(palette.secondaryButton, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.cardBorder, lineWidth: 1))
    }

    private func smallButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(palette.accent)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
