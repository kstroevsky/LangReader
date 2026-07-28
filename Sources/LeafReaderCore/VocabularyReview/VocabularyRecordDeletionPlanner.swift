import Foundation

package struct VocabularyDeletionRecord {
    package let id: String
    package let word: String

    package init(id: String, word: String) {
        self.id = id
        self.word = word
    }
}

package enum VocabularyRecordDeletionPlanner {
    package static func expandedIDs(
        requestedIDs: Set<String>,
        storedRecords: [VocabularyDeletionRecord],
        pendingRecords: [VocabularyDeletionRecord]
    ) -> Set<String> {
        guard !requestedIDs.isEmpty else { return [] }
        let allRecords = storedRecords + pendingRecords
        let matchingWords = Set(allRecords
            .filter { requestedIDs.contains($0.id) }
            .map { normalizedWord($0.word) })
        guard !matchingWords.isEmpty else { return requestedIDs }

        var expanded = requestedIDs
        expanded.formUnion(allRecords.compactMap { record in
            matchingWords.contains(normalizedWord(record.word)) ? record.id : nil
        })
        return expanded
    }

    private static func normalizedWord(_ word: String) -> String {
        VocabularyTextPolicy.canonicalVocabularyKey(word)
    }
}
