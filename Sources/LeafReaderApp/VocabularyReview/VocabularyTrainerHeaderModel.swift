import Observation
import SwiftUI

/// State behind the vocabulary trainer's header: the title, the one-line
/// summary, and the row of learning statistics.
///
/// Worth extracting for one reason above the others: the summary and every stat
/// used to be updated by **searching the view tree for a label by identifier**
/// (`findView(identifier: "vocabularySummaryLabel", in: root)`, and one lookup
/// per stat). That is a lookup that can silently find nothing — rename a view,
/// or call it before the panel is built, and the update just does not happen,
/// with no error. Here they are properties.
@Observable
final class VocabularyTrainerHeaderModel {
    var title = AppText.localized("背单词", "Vocabulary Trainer")
    /// "12 words due · 3 / 10" — the counts line under the title.
    var summary = ""
    /// The five learning stats, already formatted by the presenter.
    var stats: [VocabularyLearningStatDisplayItem] = []

    func apply(stats: VocabularyLearningStats) {
        self.stats = VocabularyLearningStatsPresenter.items(for: stats)
    }
}
