import Foundation
import LeafReaderCore

extension ReaderWindowController {
    func toggleVocabularyOccurrences(key: String) {
        guard !key.isEmpty else { return }
        if vocabularyState.expandedOccurrenceKeys.contains(key) {
            vocabularyState.expandedOccurrenceKeys.remove(key)
        } else {
            vocabularyState.expandedOccurrenceKeys.insert(key)
        }
        scheduleVocabularyPanelReload()
    }

    func openVocabularyOccurrence(id: String) {
        guard !id.isEmpty else { return }
        closeVocabularyPanel()
        DispatchQueue.main.async { [weak self] in
            self?.jumpToStoredLinkedWord(linkID: id)
        }
    }

    func vocabularySRSStatusText(_ srs: VocabularySRSState) -> String {
        let ef = String(format: "%.2f", srs.easeFactor)
        if srs.isMastered {
            return AppText.localized("已掌握 · 连续主动想起 \(srs.activeRecallStreak ?? 0) 次 · EF \(ef)", "Mastered · active recall streak \(srs.activeRecallStreak ?? 0) · EF \(ef)")
        }
        if srs.lapseCount >= 2 {
            return AppText.localized("吃力词 · 已查看答案 \(srs.lapseCount) 次 · EF \(ef)", "Hard word · answer checked \(srs.lapseCount)x · EF \(ef)")
        }
        if srs.isNew {
            return AppText.localized("新词 · 今天开始学习 · EF \(ef)", "New · start today · EF \(ef)")
        }
        if srs.isDue {
            return AppText.localized("今天复习 · 连续 \(srs.repetition) 次 · EF \(ef)", "Due today · streak \(srs.repetition) · EF \(ef)")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = srs.intervalDays == 0 ? .short : .none
        return AppText.localized(
            srs.intervalDays == 0 ? "下次：\(formatter.string(from: srs.dueDate)) · 短间隔重测 · EF \(ef)" : "下次：\(formatter.string(from: srs.dueDate)) · 间隔 \(srs.intervalDays) 天 · EF \(ef)",
            srs.intervalDays == 0 ? "Next: \(formatter.string(from: srs.dueDate)) · short retry · EF \(ef)" : "Next: \(formatter.string(from: srs.dueDate)) · \(srs.intervalDays)d · EF \(ef)"
        )
    }

    func isMeaningfulVocabularyContext(_ context: String) -> Bool {
        let contextText = VocabularyExporter.trimmed(context)
        guard contextText.count >= 3 else { return false }
        return contextText.range(of: #"[\p{L}\p{N}]"#, options: .regularExpression) != nil
    }
}
