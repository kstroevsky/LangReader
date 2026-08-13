import Foundation
import LeafReaderCore

extension ReaderWindowController {
    func backfillDictionaryAnswerAsync(vocabularyID: String?, word: String) {
        let query = VocabularyTextPolicy.normalizedVocabularyText(word)
        guard VocabularyTextPolicy.isSingleEnglishWord(query),
              let documentID = currentFileMD5 else { return }
        let localLemma = GermanLemmaResolver.lemma(for: query, language: vocabularyDocumentLanguage)

        Task { [weak self] in
            if let localAnswer = LocalDictionaryLookupService.shared.dictionaryAnswer(for: query, context: "") {
                guard !Task.isCancelled,
                      let self,
                      self.currentFileMD5 == documentID else { return }
                self.applyDictionaryAnswer(
                    localAnswer.markdown,
                    metadata: localAnswer.metadata,
                    vocabularyID: vocabularyID,
                    word: query,
                    lemma: localLemma
                )
                return
            }

            guard NetworkConnectivityMonitor.shared.isOnline else { return }
            guard let entry = try? await GermanWiktionaryDictionary.shared.lookup(query),
                  !Task.isCancelled,
                  let self,
                  self.currentFileMD5 == documentID else {
                return
            }
            self.applyDictionaryAnswer(
                entry.markdown,
                metadata: entry.metadata,
                vocabularyID: vocabularyID,
                word: query,
                lemma: entry.lemma
            )
        }
    }

    private func applyDictionaryAnswer(
        _ answer: String,
        metadata: VocabularyDictionaryMetadata,
        vocabularyID: String?,
        word: String,
        lemma: String
    ) {
        let language = vocabularyDocumentLanguage
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLemma = VocabularyTextPolicy.normalizedVocabularyText(lemma)
        let wordKey = GermanLemmaResolver.groupingKey(word: word, lemma: normalizedLemma, language: language)
        guard !trimmedAnswer.isEmpty, !wordKey.isEmpty else { return }

        if currentDocumentKind != .pdf {
            applyWebDictionaryAnswer(
                trimmedAnswer,
                metadata: metadata,
                vocabularyID: vocabularyID,
                wordKey: wordKey,
                lemma: normalizedLemma
            )
            return
        }

        var updatedRecords: [StoredPDFWordRecord] = []
        var didChangeLemma = false
        for index in storedWordRecords.indices {
            let matchingVocabularyID = vocabularyID.map { storedWordRecords[index].vocabularyID == $0 } ?? false
            let matchingWord = GermanLemmaResolver.groupingKey(
                word: storedWordRecords[index].word,
                lemma: storedWordRecords[index].lemma,
                language: language
            ) == wordKey
            guard matchingVocabularyID || matchingWord,
                  storedWordRecords[index].answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            if storedWordRecords[index].lemma != normalizedLemma {
                storedWordRecords[index].lemma = normalizedLemma
                didChangeLemma = true
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
        if didChangeLemma {
            let resolvedVocabularyID = existingPDFVocabularyID(for: word, lemma: normalizedLemma)
                ?? vocabularyID
            backfillGermanLemmaOccurrences(
                word: word,
                lemma: normalizedLemma,
                vocabularyID: resolvedVocabularyID
            )
        }
    }

    private func applyWebDictionaryAnswer(
        _ answer: String,
        metadata: VocabularyDictionaryMetadata,
        vocabularyID: String?,
        wordKey: String,
        lemma: String
    ) {
        let language = vocabularyDocumentLanguage
        var updatedRecords: [StoredWebWordRecord] = []
        for index in storedWebWordRecords.indices {
            let matchingVocabularyID = vocabularyID.map { storedWebWordRecords[index].vocabularyID == $0 } ?? false
            let matchingWord = GermanLemmaResolver.groupingKey(
                word: storedWebWordRecords[index].word,
                lemma: storedWebWordRecords[index].lemma,
                language: language
            ) == wordKey
            guard matchingVocabularyID || matchingWord,
                  storedWebWordRecords[index].answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            storedWebWordRecords[index].lemma = lemma
            storedWebWordRecords[index].answer = answer
            if storedWebWordRecords[index].dictionaryTags == nil {
                storedWebWordRecords[index].dictionaryTags = metadata.tags
            }
            if storedWebWordRecords[index].dictionaryFrequency == nil {
                storedWebWordRecords[index].dictionaryFrequency = metadata.frequency
            }
            updatedRecords.append(storedWebWordRecords[index])
        }

        guard !updatedRecords.isEmpty else { return }
        if webWordRecordStore?.upsert(updatedRecords) != true {
            saveStoredWebWordRecords()
        }
        refreshVocabularyPanelAfterLocalSave()
    }
}
