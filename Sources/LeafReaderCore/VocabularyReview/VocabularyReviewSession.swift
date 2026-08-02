import Foundation

package final class VocabularyReviewSession {
    package init() {}

    package let listPageSize = 20
    package var filter: VocabularyFilter = .due
    package var priority: VocabularyReviewPriority = .frequencyFirst
    package var dailyReviewGoal = VocabularyDailyGoalPolicy.defaultGoal
    package var reviewIndex = 0
    package var listPageIndex = 0
    package var contextShown = false
    package var answerShown = false
    package var listModeEnabled = false
    package var cardKey: String?
    package var cardShownAt = Date()
    package var answerShownAt: Date?
    package var didScoreCurrentCard = false
    package var batchKeys: [String] = []
    package var undoSRSByID: [String: VocabularySRSState] = [:]

    package func resetForReviewMode() {
        listModeEnabled = false
        reviewIndex = 0
        batchKeys = []
        resetCard(clearCardKey: true)
    }

    package func resetForListMode(filter: VocabularyFilter) {
        self.filter = filter
        listModeEnabled = true
        reviewIndex = 0
        listPageIndex = 0
        resetCard(clearCardKey: true)
    }

    package func resetCard(clearCardKey: Bool) {
        contextShown = false
        answerShown = false
        if clearCardKey {
            cardKey = nil
        }
        answerShownAt = nil
        didScoreCurrentCard = false
        undoSRSByID = [:]
    }

    package func reviewRecords(
        _ records: [VocabularyExportRecord]
    ) -> [VocabularyExportRecord] {
        let batchKeys = ensureBatch(records: records)
        var recordsByKey: [String: VocabularyExportRecord] = [:]
        for record in records {
            recordsByKey[key(for: record)] = record
        }
        return batchKeys.compactMap { key in
            guard let record = recordsByKey[key] else { return nil }
            if isShowingCurrentCard(key: key) {
                return record
            }
            guard !isDoneForToday(record) else { return nil }
            return record
        }
    }

    @discardableResult
    package func ensureBatch(
        records: [VocabularyExportRecord]
    ) -> [String] {
        var recordsByKey: [String: VocabularyExportRecord] = [:]
        for record in records {
            recordsByKey[key(for: record)] = record
        }
        let remainingCurrentBatch = batchKeys.filter { key in
            guard let record = recordsByKey[key] else { return false }
            if isShowingCurrentCard(key: key) {
                return true
            }
            return !isDoneForToday(record)
        }
        if !remainingCurrentBatch.isEmpty {
            batchKeys = remainingCurrentBatch
            return remainingCurrentBatch
        }

        let nextBatch = VocabularyReviewQueueBuilder.queue(records: records, priority: priority)
            .filter { !isDoneForToday($0) }
            .prefix(10)
            .map(key(for:))
        batchKeys = Array(nextBatch)
        return batchKeys
    }

    package func key(for record: VocabularyExportRecord) -> String {
        record.ids.sorted().joined(separator: "|")
    }

    package func isDoneForToday(_ record: VocabularyExportRecord) -> Bool {
        guard let lastReviewedAt = record.srs.lastReviewedAt,
              Calendar.current.isDateInToday(lastReviewedAt) else { return false }
        return (record.srs.activeRecallStreak ?? 0) > 0 && record.srs.intervalDays >= 1 && !record.srs.isDue
    }

    package func isShowingCurrentCard(key: String) -> Bool {
        (contextShown || answerShown) && cardKey == key
    }

    package func listRecords(
        _ records: [VocabularyExportRecord],
        matching filter: VocabularyFilter
    ) -> [VocabularyExportRecord] {
        switch filter {
        case .due:
            return records
                .filter { record in
                    guard let lastReviewedAt = record.srs.lastReviewedAt else { return false }
                    return Calendar.current.isDateInToday(lastReviewedAt)
                }
                .sorted {
                    ($0.srs.lastReviewedAt ?? $0.createdAt) > ($1.srs.lastReviewedAt ?? $1.createdAt)
                }
        case .new:
            return records
                .filter { Calendar.current.isDateInToday($0.createdAt) }
                .sorted { $0.createdAt > $1.createdAt }
        case .all:
            return records.sorted { $0.createdAt > $1.createdAt }
        }
    }

    package func listPageCount(total: Int) -> Int {
        max(1, Int(ceil(Double(total) / Double(listPageSize))))
    }

    package func currentListPageRecords(
        _ records: [VocabularyExportRecord],
        matching filter: VocabularyFilter
    ) -> (records: ArraySlice<VocabularyExportRecord>, pageIndex: Int, pageCount: Int, total: Int) {
        let visibleRecords = listRecords(records, matching: filter)
        let pageCount = listPageCount(total: visibleRecords.count)
        listPageIndex = min(max(0, listPageIndex), pageCount - 1)
        let start = listPageIndex * listPageSize
        let end = min(start + listPageSize, visibleRecords.count)
        return (visibleRecords[start..<end], listPageIndex, pageCount, visibleRecords.count)
    }

    package func goToPreviousListPage() -> Bool {
        guard listPageIndex > 0 else { return false }
        listPageIndex -= 1
        return true
    }

    @discardableResult
    package func goToNextListPage() -> Bool {
        listPageIndex += 1
        return true
    }
}
