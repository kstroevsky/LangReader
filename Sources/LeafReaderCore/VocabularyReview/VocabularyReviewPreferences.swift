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

    package var isFrequencyBackfilled: Bool {
        defaults.bool(forKey: frequencyBackfilledKey)
    }

    package func markFrequencyBackfilled() {
        defaults.set(true, forKey: frequencyBackfilledKey)
    }

    private var reviewPriorityKey: String {
        "bookSession.\(fileID).vocabularyReviewPriority"
    }

    private var dailyReviewGoalKey: String {
        "bookSession.\(fileID).vocabularyDailyReviewGoal"
    }

    private var frequencyBackfilledKey: String {
        "bookSession.\(fileID).vocabularyFrequencyBackfilled"
    }
}
