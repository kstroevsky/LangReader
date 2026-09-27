import Foundation
import LeafReaderCore

extension ReaderWindowController {
    func backfillDictionaryMetadataAsync(linkID: String, word: String) {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty,
              let workIdentity = vocabularyDocumentWorkIdentity,
              let language = vocabularyDocumentLanguageID,
              let runtime = vocabularyLanguageCatalog.resolve(language: language),
              let frequencyProvenance = VocabularyDictionaryMetadataService.frequencyProvenance(
                language: language,
                languageProfileVersion: runtime.profile.version
              ) else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let metadata = VocabularyDictionaryMetadataService.metadata(
                for: trimmedWord,
                language: language
            ) else { return }
            guard metadata.tags != nil || metadata.frequency != nil else { return }
            DispatchQueue.main.async {
                guard let self,
                      self.acceptsVocabularyDocumentWorkIdentity(workIdentity),
                      self.vocabularyDocumentLanguageID == language else { return }
                self.applyDictionaryMetadata(
                    metadata,
                    linkID: linkID,
                    frequencyProvenance: frequencyProvenance
                )
            }
        }
    }

    private func applyDictionaryMetadata(
        _ metadata: VocabularyDictionaryMetadata,
        linkID: String,
        frequencyProvenance: VocabularyFrequencyProvenance
    ) {
        var didUpdate = false

        if var pending = pendingPDFWordRecords[linkID] {
            if applyMetadata(
                metadata,
                tags: &pending.dictionaryTags,
                frequency: &pending.dictionaryFrequency,
                frequencyProvenance: &pending.dictionaryFrequencyProvenance,
                expectedFrequencyProvenance: frequencyProvenance
            ) {
                pendingPDFWordRecords[linkID] = pending
                didUpdate = true
            }
        }

        if var pending = pendingWebWordRecords[linkID] {
            if applyMetadata(
                metadata,
                tags: &pending.dictionaryTags,
                frequency: &pending.dictionaryFrequency,
                frequencyProvenance: &pending.dictionaryFrequencyProvenance,
                expectedFrequencyProvenance: frequencyProvenance
            ) {
                pendingWebWordRecords[linkID] = pending
                didUpdate = true
            }
        }

        if let index = storedWordRecords.firstIndex(where: { $0.id == linkID }) {
            var record = storedWordRecords[index]
            if applyMetadata(
                metadata,
                tags: &record.dictionaryTags,
                frequency: &record.dictionaryFrequency,
                frequencyProvenance: &record.dictionaryFrequencyProvenance,
                expectedFrequencyProvenance: frequencyProvenance
            ) {
                storedWordRecords[index] = record
                saveStoredWordRecord(record)
                didUpdate = true
            }
        }

        if let index = storedWebWordRecords.firstIndex(where: { $0.id == linkID }) {
            var record = storedWebWordRecords[index]
            if applyMetadata(
                metadata,
                tags: &record.dictionaryTags,
                frequency: &record.dictionaryFrequency,
                frequencyProvenance: &record.dictionaryFrequencyProvenance,
                expectedFrequencyProvenance: frequencyProvenance
            ) {
                storedWebWordRecords[index] = record
                saveStoredWebWordRecord(record)
                didUpdate = true
            }
        }

        guard didUpdate else { return }
        updateCurrentVocabularyExportMetadata(
            metadata,
            linkID: linkID,
            frequencyProvenance: frequencyProvenance
        )
    }

    private func applyMetadata(
        _ metadata: VocabularyDictionaryMetadata,
        tags: inout String?,
        frequency: inout Int?,
        frequencyProvenance: inout VocabularyFrequencyProvenance?,
        expectedFrequencyProvenance: VocabularyFrequencyProvenance
    ) -> Bool {
        var didUpdate = false
        if tags == nil, let metadataTags = metadata.tags {
            tags = metadataTags
            didUpdate = true
        }
        if frequency == nil, let metadataFrequency = metadata.frequency {
            frequency = metadataFrequency
            frequencyProvenance = expectedFrequencyProvenance
            didUpdate = true
        }
        return didUpdate
    }

    private func updateCurrentVocabularyExportMetadata(
        _ metadata: VocabularyDictionaryMetadata,
        linkID: String,
        frequencyProvenance: VocabularyFrequencyProvenance
    ) {
        for index in currentVocabularyExportRecords.indices where currentVocabularyExportRecords[index].ids.contains(linkID) {
            currentVocabularyExportRecords[index] = currentVocabularyExportRecords[index].withDictionaryMetadata(
                tags: metadata.tags,
                frequency: metadata.frequency,
                frequencyProvenance: metadata.frequency == nil ? nil : frequencyProvenance
            )
        }
    }
}
