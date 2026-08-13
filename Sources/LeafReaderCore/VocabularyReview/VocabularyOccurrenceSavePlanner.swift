package struct VocabularyOccurrenceSavePlan {
    package let recordsToInsert: [StoredPDFWordRecord]
    package let foundCount: Int
}

/// Applies the save workflow's occurrence identity rules independently of PDFKit
/// and SQLite. Discovery may return the same occurrence more than once, and the
/// selected occurrence has already been acknowledged before discovery finishes.
package enum VocabularyOccurrenceSavePlanner {
    package static func plan(
        selectedRecord: StoredPDFWordRecord,
        discoveredRecords: [StoredPDFWordRecord],
        existingRecordKeys: Set<String>
    ) -> VocabularyOccurrenceSavePlan {
        var foundKeys = Set<String>()
        var knownKeys = existingRecordKeys
        var recordsToInsert: [StoredPDFWordRecord] = []

        for record in discoveredRecords + [selectedRecord] {
            let key = record.occurrenceKey
            guard foundKeys.insert(key).inserted else { continue }
            guard knownKeys.insert(key).inserted else { continue }
            recordsToInsert.append(record)
        }

        return VocabularyOccurrenceSavePlan(
            recordsToInsert: recordsToInsert,
            foundCount: foundKeys.count
        )
    }
}
