import Foundation

package struct VocabularyLearningStats: Equatable {
    package let totalCount: Int
    package let reviewedTodayCount: Int
    package let masteredCount: Int
    package let recallRatePercent: Int?
    package let streakDays: Int
}

package enum VocabularyLearningStatsCalculator {
    package static func stats(
        records: [VocabularyExportRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> VocabularyLearningStats {
        let reviewedToday = records.filter { record in
            guard let lastReviewedAt = record.srs.lastReviewedAt else { return false }
            return calendar.isDate(lastReviewedAt, inSameDayAs: now)
        }.count
        let totalReviews = records.reduce(0) { $0 + $1.srs.reviewCount }
        let totalLapses = records.reduce(0) { $0 + $1.srs.lapseCount }
        let recallRate: Int? = totalReviews > 0
            ? Int((Double(max(0, totalReviews - totalLapses)) / Double(totalReviews) * 100).rounded())
            : nil

        return VocabularyLearningStats(
            totalCount: records.count,
            reviewedTodayCount: reviewedToday,
            masteredCount: records.filter { $0.srs.isMastered }.count,
            recallRatePercent: recallRate,
            streakDays: activeDayStreak(records: records, now: now, calendar: calendar)
        )
    }

    private static func activeDayStreak(
        records: [VocabularyExportRecord],
        now: Date,
        calendar: Calendar
    ) -> Int {
        let activeDays = Set(records.compactMap { record -> Date? in
            guard let lastReviewedAt = record.srs.lastReviewedAt else { return nil }
            return calendar.startOfDay(for: lastReviewedAt)
        })
        var cursor = calendar.startOfDay(for: now)
        var streak = 0
        while activeDays.contains(cursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previousDay
        }
        return streak
    }
}
