import Foundation
import LeafReaderCore

extension ReaderWindowController {
    func backfillVocabularyFrequenciesIfNeeded(
        progress: @escaping (_ word: String, _ current: Int, _ total: Int) -> Void,
        completion: @escaping () -> Void
    ) {
        guard let preferences = vocabularyReviewPreferences else {
            completion()
            return
        }
        guard let language = vocabularyDocumentLanguageID,
              let runtime = vocabularyLanguageCatalog.resolve(language: language),
              let provenance = VocabularyDictionaryMetadataService.frequencyProvenance(
                language: language,
                languageProfileVersion: runtime.profile.version
              ) else {
            completion()
            return
        }
        let languageRevision = vocabularyLanguageRevision
        let plan = vocabularyFrequencyBackfillPlan(provenance: provenance)
        guard !preferences.isFrequencyBackfilled(for: plan.scope) else {
            completion()
            return
        }
        let service = VocabularyFrequencyBackfillService()
        service.backfillIfNeeded(items: plan.items, progress: { progressState in
            progress(progressState.word, progressState.current, progressState.total)
        }) { [weak self] result in
            guard let self,
                  self.vocabularyLanguageRevision == languageRevision,
                  self.vocabularyDocumentLanguageID == language else {
                completion()
                return
            }
            let currentPlan = self.vocabularyFrequencyBackfillPlan(provenance: provenance)
            guard currentPlan.scope == plan.scope else {
                completion()
                return
            }
            guard self.applyVocabularyFrequencies(
                result.frequenciesByID,
                provenance: provenance
            ) else {
                completion()
                return
            }
            if result.isComplete {
                preferences.markFrequencyBackfilled(VocabularyFrequencyBackfillCompletion(
                    scope: plan.scope,
                    terminalNotFoundRecordIDs: result.terminalNotFoundRecordIDs
                ))
            }
            completion()
        }
    }

    private func vocabularyFrequencyBackfillPlan(
        provenance: VocabularyFrequencyProvenance
    ) -> VocabularyFrequencyBackfillPlan {
        switch currentDocumentKind {
        case .pdf:
            return VocabularyDictionaryMetadataService.pdfFrequencyBackfillPlan(
                storedWordRecords,
                provenance: provenance
            )
        case .epub, .docx:
            return VocabularyDictionaryMetadataService.webFrequencyBackfillPlan(
                storedWebWordRecords,
                provenance: provenance
            )
        }
    }

    private func applyVocabularyFrequencies(
        _ frequenciesByID: [String: Int],
        provenance: VocabularyFrequencyProvenance
    ) -> Bool {
        guard !frequenciesByID.isEmpty else { return true }

        switch currentDocumentKind {
        case .pdf:
            var staged = storedWordRecords
            var changed: [StoredPDFWordRecord] = []
            for index in staged.indices {
                guard let frequency = frequenciesByID[staged[index].id],
                      staged[index].language == nil || staged[index].language == provenance.language,
                      VocabularyDictionaryMetadataService.isFrequencyBackfillEligible(
                        word: staged[index].word,
                        answer: staged[index].answer
                      ) else { continue }
                staged[index].dictionaryFrequency = frequency
                staged[index].dictionaryFrequencyProvenance = provenance
                changed.append(staged[index])
            }
            guard Set(changed.map(\.id)) == Set(frequenciesByID.keys) else { return false }
            guard pdfWordRecordStore?.upsert(changed) == true else { return false }
            storedWordRecords = staged
        case .epub, .docx:
            var staged = storedWebWordRecords
            var changed: [StoredWebWordRecord] = []
            for index in staged.indices {
                guard let frequency = frequenciesByID[staged[index].id],
                      staged[index].language == nil || staged[index].language == provenance.language,
                      VocabularyDictionaryMetadataService.isFrequencyBackfillEligible(
                        word: staged[index].word,
                        answer: staged[index].answer
                      ) else { continue }
                staged[index].dictionaryFrequency = frequency
                staged[index].dictionaryFrequencyProvenance = provenance
                changed.append(staged[index])
            }
            guard Set(changed.map(\.id)) == Set(frequenciesByID.keys) else { return false }
            guard webWordRecordStore?.upsert(changed) == true else { return false }
            storedWebWordRecords = staged
        }

        if !frequenciesByID.isEmpty {
            currentVocabularyExportRecords = makeCurrentVocabularyExportRecords()
        }
        return true
    }
}
