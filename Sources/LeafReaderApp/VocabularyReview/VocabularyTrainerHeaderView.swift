import SwiftUI
import LeafReaderCore

/// The vocabulary trainer's header: icon, title, the summary line, and the row
/// of learning stat cards.
///
/// Replaces a hand-built `NSStackView` of stat cards — each a view with two
/// labels and six constraints — plus the identifier-driven updates that reached
/// back into it.
struct VocabularyTrainerHeaderView: View {
    @Bindable var model: VocabularyTrainerHeaderModel
    let theme: ReaderTheme
    /// Width of the filter tabs, which are an AppKit view laid over this one's
    /// top-right. The title row keeps clear of them; the summary and the stat
    /// cards still use the full width.
    var reservedTrailingWidth: CGFloat = 0

    private var palette: VocabularyCardPalette { VocabularyCardPalette(theme: theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "text.book.closed")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(palette.accent)
                Text(model.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                    .fixedSize()
                Spacer(minLength: 0)
            }
            .padding(.trailing, reservedTrailingWidth)

            Text(model.summary)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.secondaryText)
                .accessibilityIdentifier(VocabularyTrainerAccessibility.summary)

            HStack(spacing: 8) {
                ForEach(model.stats, id: \.valueIdentifier) { item in
                    statCard(item)
                }
            }
        }
    }

    private func statCard(_ item: VocabularyLearningStatDisplayItem) -> some View {
        VStack(spacing: 4) {
            Text(item.value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.primaryText)
                .accessibilityIdentifier(item.valueIdentifier)
            Text(item.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.cardBorder, lineWidth: 1))
    }
}

enum VocabularyTrainerAccessibility {
    static let summary = "trainer.summary"
    static let header = "trainer.header"
}
