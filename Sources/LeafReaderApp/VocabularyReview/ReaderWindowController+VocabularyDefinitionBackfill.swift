import Foundation

extension ReaderWindowController {
    func backfillDictionaryAnswerAsync(vocabularyID: String?, word: String) {
        let query = VocabularyTextPolicy.normalizedVocabularyText(word)
        guard VocabularyTextPolicy.isSingleEnglishWord(query) else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            if let localAnswer = LocalDictionaryLookupService.shared.dictionaryAnswer(for: query, context: "") {
                DispatchQueue.main.async {
                    self?.applyDictionaryAnswer(
                        localAnswer.markdown,
                        metadata: localAnswer.metadata,
                        vocabularyID: vocabularyID,
                        word: query
                    )
                }
                return
            }

            guard NetworkConnectivityMonitor.shared.isOnline else { return }
            GermanWiktionaryDictionary.shared.lookup(query) { [weak self] result in
                guard case .success(let entry) = result else { return }
                DispatchQueue.main.async {
                    self?.applyDictionaryAnswer(
                        entry.markdown,
                        metadata: entry.metadata,
                        vocabularyID: vocabularyID,
                        word: query
                    )
                }
            }
        }
    }

    private func applyDictionaryAnswer(
        _ answer: String,
        metadata: VocabularyDictionaryMetadata,
        vocabularyID: String?,
        word: String
    ) {
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordKey = VocabularyTextPolicy.canonicalVocabularyKey(word)
        guard !trimmedAnswer.isEmpty, !wordKey.isEmpty else { return }

        var updatedRecords: [StoredPDFWordRecord] = []
        for index in storedWordRecords.indices {
            let matchingVocabularyID = vocabularyID.map { storedWordRecords[index].vocabularyID == $0 } ?? false
            let matchingWord = VocabularyTextPolicy.canonicalVocabularyKey(storedWordRecords[index].word) == wordKey
            guard matchingVocabularyID || matchingWord,
                  storedWordRecords[index].answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            storedWordRecords[index].answer = trimmedAnswer
            if storedWordRecords[index].dictionaryTags == nil {
                storedWordRecords[index].dictionaryTags = metadata.tags
            }
            if storedWordRecords[index].dictionaryFrequency == nil {
                storedWordRecords[index].dictionaryFrequency = metadata.frequency
            }
            updatedRecords.append(storedWordRecords[index])
        }

        guard !updatedRecords.isEmpty else { return }
        if pdfWordRecordStore?.upsert(updatedRecords) != true {
            saveStoredWordRecords()
        }
        refreshVocabularyPanelAfterLocalSave()
    }
}
