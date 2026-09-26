import Foundation
import LeafReaderCore

struct VocabularyDictionaryBackfillItem {
    let id: String
    let word: String
    let language: VocabularyLanguageID
}

enum VocabularyDictionaryMetadataService {
    static func metadata(
        for word: String,
        language: VocabularyLanguageID,
        lookupService: DictionaryLookupService = LocalDictionaryLookupService.shared
    ) -> VocabularyDictionaryMetadata? {
        guard language == .english else { return nil }
        return lookupService.metadata(for: word)
    }

    static func frequency(from value: String) -> Int? {
        guard let frequency = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)), frequency > 0 else {
            return nil
        }
        return frequency
    }

    static func shouldBackfillFrequency(word: String, answer: String, frequency: Int?) -> Bool {
        guard frequency == nil else { return false }
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return VocabularyTextPolicy.speakableWord(word) != nil
    }

    static func pdfFrequencyBackfillItems(
        _ records: [StoredPDFWordRecord],
        language: VocabularyLanguageID
    ) -> [VocabularyDictionaryBackfillItem] {
        guard language == .english else { return [] }
        return records.compactMap { record in
            shouldBackfillFrequency(word: record.word, answer: record.answer, frequency: record.dictionaryFrequency)
                ? VocabularyDictionaryBackfillItem(id: record.id, word: record.word, language: language)
                : nil
        }
    }

    static func webFrequencyBackfillItems(
        _ records: [StoredWebWordRecord],
        language: VocabularyLanguageID
    ) -> [VocabularyDictionaryBackfillItem] {
        guard language == .english else { return [] }
        return records.compactMap { record in
            shouldBackfillFrequency(word: record.word, answer: record.answer, frequency: record.dictionaryFrequency)
                ? VocabularyDictionaryBackfillItem(id: record.id, word: record.word, language: language)
                : nil
        }
    }
}
