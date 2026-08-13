import Foundation
import LeafReaderCore

package struct VocabularyLearningStatDisplayItem: Equatable {
    package let title: String
    package let value: String
    package let valueIdentifier: String
}

/// Formats domain learning statistics for the vocabulary panel and owns the
/// stable accessibility identifiers used by that presentation.
package enum VocabularyLearningStatsPresenter {
    package static let containerIdentifier = "vocabularyStatsContainer"
    private static let totalIdentifier = "vocabularyStatTotalValue"
    private static let reviewedTodayIdentifier = "vocabularyStatReviewedTodayValue"
    private static let masteredIdentifier = "vocabularyStatMasteredValue"
    private static let recallRateIdentifier = "vocabularyStatRecallRateValue"
    private static let streakIdentifier = "vocabularyStatStreakValue"

    package static func items(for stats: VocabularyLearningStats) -> [VocabularyLearningStatDisplayItem] {
        [
            VocabularyLearningStatDisplayItem(
                title: AppText.localized("总词数", "Words"),
                value: "\(stats.totalCount)",
                valueIdentifier: totalIdentifier
            ),
            VocabularyLearningStatDisplayItem(
                title: AppText.localized("今日复习", "Today"),
                value: "\(stats.reviewedTodayCount)",
                valueIdentifier: reviewedTodayIdentifier
            ),
            VocabularyLearningStatDisplayItem(
                title: AppText.localized("已掌握", "Mastered"),
                value: "\(stats.masteredCount)",
                valueIdentifier: masteredIdentifier
            ),
            VocabularyLearningStatDisplayItem(
                title: AppText.localized("正确率", "Recall"),
                value: recallRateText(stats.recallRatePercent),
                valueIdentifier: recallRateIdentifier
            ),
            VocabularyLearningStatDisplayItem(
                title: AppText.localized("连续天数", "Streak"),
                value: "\(stats.streakDays)",
                valueIdentifier: streakIdentifier
            )
        ]
    }

    package static func recallRateText(_ value: Int?) -> String {
        value.map { "\($0)%" } ?? "--"
    }
}
