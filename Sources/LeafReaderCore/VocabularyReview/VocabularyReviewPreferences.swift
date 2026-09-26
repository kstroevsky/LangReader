import Foundation

/// `UserDefaults` provides synchronized access; this value only scopes keys to
/// one document and does not add mutable storage of its own.
package struct VocabularyReviewPreferences: @unchecked Sendable {
    private let fileID: String
    private let defaults: UserDefaults

    package init(fileID: String, defaults: UserDefaults = .standard) {
        self.fileID = fileID
        self.defaults = defaults
    }

    package var reviewPriority: VocabularyReviewPriority {
        get {
            guard let rawValue = defaults.string(forKey: reviewPriorityKey),
                  let priority = VocabularyReviewPriority(rawValue: rawValue) else {
                return .frequencyFirst
            }
            return priority
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: reviewPriorityKey)
        }
    }

    package var dailyReviewGoal: Int {
        get {
            let goal = defaults.integer(forKey: dailyReviewGoalKey)
            return VocabularyDailyGoalPolicy.normalizedGoal(goal)
        }
        nonmutating set {
            defaults.set(VocabularyDailyGoalPolicy.normalizedGoal(newValue), forKey: dailyReviewGoalKey)
        }
    }

    package var frequencyBackfillCompletion: VocabularyFrequencyBackfillCompletion? {
        guard let data = defaults.data(forKey: frequencyBackfillCompletionKey) else { return nil }
        return try? JSONDecoder().decode(VocabularyFrequencyBackfillCompletion.self, from: data)
    }

    package func isFrequencyBackfilled(for scope: VocabularyFrequencyBackfillScope) -> Bool {
        frequencyBackfillCompletion?.scope == scope
    }

    package func markFrequencyBackfilled(_ completion: VocabularyFrequencyBackfillCompletion) {
        guard let data = try? JSONEncoder().encode(completion) else { return }
        defaults.set(data, forKey: frequencyBackfillCompletionKey)
    }

    private var reviewPriorityKey: String {
        "bookSession.\(fileID).vocabularyReviewPriority"
    }

    private var dailyReviewGoalKey: String {
        "bookSession.\(fileID).vocabularyDailyReviewGoal"
    }

    private var frequencyBackfillCompletionKey: String {
        "bookSession.\(fileID).vocabularyFrequencyBackfillCompletion.v1"
    }
}
