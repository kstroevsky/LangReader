import Foundation
import LeafReaderCore

struct VocabularyFrequencyBackfillProgress {
    let word: String
    let current: Int
    let total: Int
}

struct VocabularyFrequencyBackfillResult {
    let frequenciesByID: [String: Int]
    let terminalNotFoundRecordIDs: Set<String>
    let incompleteRecordIDs: Set<String>

    var isComplete: Bool { incompleteRecordIDs.isEmpty }
}

final class VocabularyFrequencyBackfillService {
    private let metadataService: VocabularyDictionaryMetadataService.Type

    init(
        metadataService: VocabularyDictionaryMetadataService.Type = VocabularyDictionaryMetadataService.self
    ) {
        self.metadataService = metadataService
    }

    func backfillIfNeeded(
        items: [VocabularyDictionaryBackfillItem],
        progress: @escaping (VocabularyFrequencyBackfillProgress) -> Void,
        completion: @escaping (VocabularyFrequencyBackfillResult) -> Void
    ) {
        let callbacks = VocabularyFrequencyBackfillCallbacks(
            progress: progress,
            completion: completion
        )
        if items.isEmpty {
            callbacks.complete(VocabularyFrequencyBackfillResult(
                frequenciesByID: [:],
                terminalNotFoundRecordIDs: [],
                incompleteRecordIDs: []
            ))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [metadataService] in
            var frequenciesByID: [String: Int] = [:]
            var terminalNotFoundRecordIDs = Set<String>()
            var incompleteRecordIDs = Set<String>()
            for (offset, item) in items.enumerated() {
                DispatchQueue.main.async {
                    callbacks.report(VocabularyFrequencyBackfillProgress(word: item.word, current: offset + 1, total: items.count))
                }
                guard item.provenance.language == item.language,
                      item.provenance.provider.supports(item.language) else {
                    incompleteRecordIDs.insert(item.id)
                    continue
                }
                guard let metadata = metadataService.metadata(
                    for: item.word,
                    language: item.language
                ) else {
                    terminalNotFoundRecordIDs.insert(item.id)
                    continue
                }
                guard let frequency = metadata.frequency else {
                    terminalNotFoundRecordIDs.insert(item.id)
                    continue
                }
                frequenciesByID[item.id] = frequency
            }
            DispatchQueue.main.async {
                callbacks.complete(VocabularyFrequencyBackfillResult(
                    frequenciesByID: frequenciesByID,
                    terminalNotFoundRecordIDs: terminalNotFoundRecordIDs,
                    incompleteRecordIDs: incompleteRecordIDs
                ))
            }
        }
    }
}

private final class VocabularyFrequencyBackfillCallbacks: @unchecked Sendable {
    private let progress: (VocabularyFrequencyBackfillProgress) -> Void
    private let completion: (VocabularyFrequencyBackfillResult) -> Void

    init(
        progress: @escaping (VocabularyFrequencyBackfillProgress) -> Void,
        completion: @escaping (VocabularyFrequencyBackfillResult) -> Void
    ) {
        self.progress = progress
        self.completion = completion
    }

    func report(_ value: VocabularyFrequencyBackfillProgress) {
        progress(value)
    }

    func complete(_ value: VocabularyFrequencyBackfillResult) {
        completion(value)
    }
}
