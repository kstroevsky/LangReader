import Foundation

/// Enriches a vocabulary record with persisted dictionary metadata when the
/// record is eligible and does not already contain it.
///
/// The policy is independent of which screen requested the enrichment; lookup
/// and persistence remain injected capabilities so Core owns no database or UI.
package enum VocabularyDictionaryMetadataEnrichmentPolicy {
    package static func enrichedRecord(
        for record: VocabularyExportRecord,
        metadataLookup: (String) -> (tags: String?, frequency: Int?),
        persistTags: (String, VocabularyExportRecord) -> Void
    ) -> VocabularyExportRecord {
        if record.dictionaryTags?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return record
        }
        guard VocabularyTextPolicy.speakableWord(record.word) != nil else {
            return record
        }
        let metadata = metadataLookup(record.word)
        guard let tags = metadata.tags?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tags.isEmpty else {
            return record
        }
        persistTags(tags, record)
        return record.withDictionaryMetadata(tags: tags)
    }
}
