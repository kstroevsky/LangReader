import Foundation
import LeafReaderCore

struct VocabularyDictionaryBackfillItem: Equatable {
    let id: String
    let word: String
    let language: VocabularyLanguageID
    let lexicalKey: String?
    let provenance: VocabularyFrequencyProvenance

    var identity: VocabularyFrequencyBackfillRecordIdentity {
        VocabularyFrequencyBackfillRecordIdentity(
            id: id,
            lookupText: VocabularyTextPolicy.normalizedVocabularyText(word),
            language: language,
            lexicalKey: lexicalKey
        )
    }
}

struct VocabularyFrequencyBackfillPlan: Equatable {
    let scope: VocabularyFrequencyBackfillScope
    let items: [VocabularyDictionaryBackfillItem]
}

enum VocabularyDictionaryMetadataService {
    static let frequencyProviderDescriptor = VocabularyProviderDescriptor(
        id: "dictionary.ecdict",
        version: "ecdict-v1",
        supportedLanguageRanges: [VocabularyLanguageRange(language: .english, includesDescendants: true)]
    )

    static func frequencyProvenance(
        language: VocabularyLanguageID,
        languageProfileVersion: String
    ) -> VocabularyFrequencyProvenance? {
        guard frequencyProviderDescriptor.supports(language) else { return nil }
        return VocabularyFrequencyProvenance(
            language: language,
            languageProfileVersion: languageProfileVersion,
            provider: frequencyProviderDescriptor
        )
    }

    static func metadata(
        for word: String,
        language: VocabularyLanguageID,
        lookupService: DictionaryLookupService = LocalDictionaryLookupService.shared
    ) -> VocabularyDictionaryMetadata? {
        guard frequencyProviderDescriptor.supports(language) else { return nil }
        return lookupService.metadata(for: word)
    }

    static func frequency(from value: String) -> Int? {
        guard let frequency = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)), frequency > 0 else {
            return nil
        }
        return frequency
    }

    static func isFrequencyBackfillEligible(word: String, answer: String) -> Bool {
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return VocabularyTextPolicy.speakableWord(word) != nil
    }

    static func shouldBackfillFrequency(
        word: String,
        answer: String,
        frequency: Int?,
        storedProvenance: VocabularyFrequencyProvenance?,
        expectedProvenance: VocabularyFrequencyProvenance
    ) -> Bool {
        guard isFrequencyBackfillEligible(word: word, answer: answer) else { return false }
        return frequency == nil || storedProvenance != expectedProvenance
    }

    static func pdfFrequencyBackfillPlan(
        _ records: [StoredPDFWordRecord],
        provenance: VocabularyFrequencyProvenance
    ) -> VocabularyFrequencyBackfillPlan {
        let eligible = records.compactMap { record -> VocabularyDictionaryBackfillItem? in
            guard record.language == nil || record.language == provenance.language,
                  isFrequencyBackfillEligible(word: record.word, answer: record.answer) else { return nil }
            return VocabularyDictionaryBackfillItem(
                id: record.id,
                word: record.word,
                language: provenance.language,
                lexicalKey: record.lexicalKey,
                provenance: provenance
            )
        }
        return VocabularyFrequencyBackfillPlan(
            scope: VocabularyFrequencyBackfillScope(
                provenance: provenance,
                eligibleRecords: eligible.map(\.identity)
            ),
            items: eligible.filter { item in
                guard let record = records.first(where: { $0.id == item.id }) else { return false }
                return shouldBackfillFrequency(
                    word: record.word,
                    answer: record.answer,
                    frequency: record.dictionaryFrequency,
                    storedProvenance: record.dictionaryFrequencyProvenance,
                    expectedProvenance: provenance
                )
            }
        )
    }

    static func webFrequencyBackfillPlan(
        _ records: [StoredWebWordRecord],
        provenance: VocabularyFrequencyProvenance
    ) -> VocabularyFrequencyBackfillPlan {
        let eligible = records.compactMap { record -> VocabularyDictionaryBackfillItem? in
            guard record.language == nil || record.language == provenance.language,
                  isFrequencyBackfillEligible(word: record.word, answer: record.answer) else { return nil }
            return VocabularyDictionaryBackfillItem(
                id: record.id,
                word: record.word,
                language: provenance.language,
                lexicalKey: record.lexicalKey,
                provenance: provenance
            )
        }
        return VocabularyFrequencyBackfillPlan(
            scope: VocabularyFrequencyBackfillScope(
                provenance: provenance,
                eligibleRecords: eligible.map(\.identity)
            ),
            items: eligible.filter { item in
                guard let record = records.first(where: { $0.id == item.id }) else { return false }
                return shouldBackfillFrequency(
                    word: record.word,
                    answer: record.answer,
                    frequency: record.dictionaryFrequency,
                    storedProvenance: record.dictionaryFrequencyProvenance,
                    expectedProvenance: provenance
                )
            }
        )
    }
}
