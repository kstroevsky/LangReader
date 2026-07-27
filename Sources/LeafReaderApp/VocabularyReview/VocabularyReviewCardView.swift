import SwiftUI
import LeafReaderCore

/// One flashcard in the vocabulary review.
///
/// Replaces `VocabularyReviewCardBuilder` and its two helper builders — ~310
/// lines that rebuilt a tree of `NSView`s and constraints from scratch on every
/// tap. The three faces of the card (word / sentence / answer) are one view
/// here, differing by `model.phase`.
struct VocabularyReviewCardView: View {
    @Bindable var model: VocabularyReviewCardModel
    let theme: ReaderTheme

    private var palette: VocabularyCardPalette { VocabularyCardPalette(theme: theme) }

    var body: some View {
        if let emptyMessage = model.emptyMessage {
            Text(emptyMessage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, model.tags == nil ? 20 : 16)
            footer
                .padding(.top, 14)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.cardBorder, lineWidth: 1))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Text(model.word)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if model.hasPronunciation {
                    Button {
                        model.action?(.speak)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(palette.accent)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .help(AppText.localized("播放单词发音", "Play word pronunciation"))
                    .accessibilityIdentifier(VocabularyReviewAccessibility.speakButton)
                }
                Spacer(minLength: 0)
            }
            if let tags = model.tags {
                Text(tags)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .prompt:
            // Deliberately blank: the prompt is the word alone.
            Color.clear
        // Both text phases scroll rather than growing: the card is pinned into a
        // fixed region of the panel, so content that asks for its ideal height
        // pushes the whole panel taller instead of scrolling inside the card.
        case .context:
            if let contextText = model.contextText {
                scrollingText(contextText)
            }
        case .answer:
            if let answerText = model.answerText {
                scrollingText(answerText)
            }
        }
    }

    private func scrollingText(_ text: AttributedString) -> some View {
        ScrollView {
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .scrollContentBackground(.hidden)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            ForEach(model.footerActions, id: \.action) { entry in
                Button {
                    model.action?(entry.action)
                } label: {
                    Text(entry.title)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 108, height: 36)
                }
                .buttonStyle(.plain)
                .background(
                    entry.isPrimary ? palette.primaryButton : palette.secondaryButton,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .foregroundStyle(entry.isPrimary ? palette.primaryButtonText : palette.primaryText)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(entry.isPrimary ? .clear : palette.cardBorder, lineWidth: 1)
                )
                .accessibilityIdentifier(entry.action.accessibilityIdentifier)
            }
        }
        .frame(height: 44)
    }
}

extension VocabularyReviewAction {
    var accessibilityIdentifier: String {
        switch self {
        case .know: return "review.know"
        case .doNotKnow: return "review.doNotKnow"
        case .rememberedAfterContext: return "review.remembered"
        case .forgot: return "review.forgot"
        case .next: return "review.next"
        case .undo: return "review.undo"
        case .speak: return "review.speak"
        }
    }
}

/// The review card's colours, mirroring the `vocabulary*Color(for:)` helpers the
/// AppKit builder called so the card looks unchanged.
struct VocabularyCardPalette {
    let cardBackground: Color
    let cardBorder: Color
    let primaryText: Color
    let secondaryText: Color
    let bodyText: Color
    let accent: Color
    let primaryButton: Color
    let primaryButtonText: Color
    let secondaryButton: Color

    init(theme: ReaderTheme) {
        // The AppKit builder reached these through `vocabulary*Color(for:)` on
        // the controller, which are one-line forwards to the theme. Reading the
        // theme directly keeps the card identical without a second palette.
        cardBackground = Color(nsColor: theme.vocabularyCardBackgroundColor)
        cardBorder = Color(nsColor: theme.vocabularyCardBorderColor)
        primaryText = Color(nsColor: theme.vocabularyPrimaryTextColor)
        secondaryText = Color(nsColor: theme.vocabularySecondaryTextColor)
        bodyText = Color(nsColor: theme.vocabularyBodyTextColor)
        accent = Color(nsColor: theme.vocabularyAccentColor)
        primaryButton = Color(nsColor: theme.accentColor)
        primaryButtonText = Color(nsColor: theme.primaryActionTextColor)
        secondaryButton = Color(nsColor: theme.vocabularyButtonBackgroundColor)
    }
}

enum VocabularyReviewAccessibility {
    static let speakButton = "review.speak"
    static let card = "review.card"
}
