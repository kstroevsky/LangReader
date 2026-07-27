import Observation
import SwiftUI
import LeafReaderCore

/// Which face of the flashcard is showing.
///
/// The three phases were previously implied by two booleans on the session
/// (`contextShown`, `answerShown`) that the card builder branched on, with the
/// fourth combination meaningless. Naming them makes the impossible state
/// unrepresentable and the footer's buttons a function of the phase.
enum VocabularyReviewPhase: Equatable {
    /// Just the word: do you know it?
    case prompt
    /// The sentence it was found in, as a hint.
    case context
    /// The full dictionary answer, and the chance to score it.
    case answer
}

/// What the card's footer buttons do. The controller owns the SRS scoring and
/// card advancement; this only says which one was pressed.
enum VocabularyReviewAction: Equatable {
    case know
    case doNotKnow
    case rememberedAfterContext
    case forgot
    case next
    case undo
    case speak
}

/// State behind one flashcard in the vocabulary review.
///
/// The card used to be built imperatively three times over — a builder, a
/// content builder and a footer builder, ~310 lines of `NSView`s and
/// constraints, re-created from scratch on every tap. Here it is the card's
/// data plus which phase it is in.
///
/// Rich text is produced by the existing AppKit renderers, injected as closures
/// and bridged to `AttributedString` — the same arrangement `VocabularyDetailModel`
/// already uses, so markdown is not re-implemented for a second screen.
@Observable
final class VocabularyReviewCardModel {
    var word = ""
    /// The ECDICT tag line ("zk gk · CET4"), when the word has one.
    var tags: String?
    var phase: VocabularyReviewPhase = .prompt
    /// Whether this card has been scored, which is what offers Undo.
    var didScore = false
    var canUndo = false
    var hasPronunciation = false

    /// Set when there is no card to show, e.g. nothing due today.
    var emptyMessage: String?

    /// The source sentence, already resolved to either the real context or the
    /// "no sentence available" line.
    @ObservationIgnored var makeContext: (() -> NSAttributedString)?
    /// Context plus the dictionary answer, rendered from markdown.
    @ObservationIgnored var makeAnswer: (() -> NSAttributedString)?
    @ObservationIgnored var action: ((VocabularyReviewAction) -> Void)?

    var contextText: AttributedString? {
        makeContext.map { AttributedString($0()) }
    }

    var answerText: AttributedString? {
        makeAnswer.map { AttributedString($0()) }
    }

    /// The footer's buttons for the current phase, primary first.
    ///
    /// This is the rule the three `add*Footer` methods encoded between them:
    /// each phase offers a way forward and a way to ask for more, and only a
    /// scored answer can be undone.
    var footerActions: [(action: VocabularyReviewAction, title: String, isPrimary: Bool)] {
        switch phase {
        case .prompt:
            return [
                (.know, AppText.localized("认识", "Know"), true),
                (.doNotKnow, AppText.localized("不认识", "Do not know"), false)
            ]
        case .context:
            return [
                (.rememberedAfterContext, AppText.localized("想起来了", "Remembered"), true),
                (.forgot, AppText.localized("没想起来", "Forgot"), false)
            ]
        case .answer:
            var actions: [(VocabularyReviewAction, String, Bool)] = []
            if didScore, canUndo {
                actions.append((.undo, AppText.localized("撤销", "Undo"), false))
            }
            actions.append((.next, AppText.localized("下一个", "Next"), true))
            return actions
        }
    }
}
