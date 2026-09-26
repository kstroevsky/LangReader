import Foundation
import LeafReaderCore

extension ReaderWindowController {
    func backfillDictionaryAnswerAsync(vocabularyID: String?, word: String) {
        let query = VocabularyTextPolicy.normalizedVocabularyText(word)
        guard VocabularyTextPolicy.isSingleEnglishWord(query),
              let documentID = currentFileMD5,
              let language = vocabularyDocumentLanguageID,
              let runtime = vocabularyLanguageCatalog.resolve(language: language),
              let provider = runtime.definitions else { return }
        let languageRevision = vocabularyLanguageRevision
        let appleLanguage = language.appleNaturalLanguage
        let localLemma = GermanLemmaResolver.lemma(for: query, language: appleLanguage)

        Task { [weak self] in
            guard let definition = try? await provider.definition(for: VocabularyDefinitionRequest(
                language: language,
                lemma: localLemma,
                surfaceForm: query,
                context: ""
            )),
                  !Task.isCancelled,
                  let self,
                  self.currentFileMD5 == documentID,
                  self.vocabularyLanguageRevision == languageRevision,
                  self.vocabularyDocumentLanguageID == language else {
                return
            }
            self.applyDictionaryAnswer(
                definition.markdown,
                metadata: VocabularyDictionaryMetadata(
                    tags: definition.tags,
                    frequency: definition.frequency
                ),
                vocabularyID: vocabularyID,
                word: query,
                lemma: definition.resolvedLemma ?? localLemma,
                language: language,
                frequencyProvenance: VocabularyFrequencyProvenance(
                    language: language,
                    languageProfileVersion: runtime.profile.version,
                    provider: definition.provenance
                )
            )
        }
    }

    private func applyDictionaryAnswer(
        _ answer: String,
        metadata: VocabularyDictionaryMetadata,
        vocabularyID: String?,
        word: String,
        lemma: String,
        language: VocabularyLanguageID,
        frequencyProvenance: VocabularyFrequencyProvenance
    ) {
        let appleLanguage = language.appleNaturalLanguage
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLemma = VocabularyTextPolicy.normalizedVocabularyText(lemma)
        let wordKey = GermanLemmaResolver.groupingKey(word: word, lemma: normalizedLemma, language: appleLanguage)
        guard !trimmedAnswer.isEmpty, !wordKey.isEmpty else { return }

        if currentDocumentKind != .pdf {
            applyWebDictionaryAnswer(
                trimmedAnswer,
                metadata: metadata,
                vocabularyID: vocabularyID,
                wordKey: wordKey,
                lemma: normalizedLemma,
                language: language,
                frequencyProvenance: frequencyProvenance
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
                language: appleLanguage
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
                if metadata.frequency != nil {
                    storedWordRecords[index].dictionaryFrequencyProvenance = frequencyProvenance
                }
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
        lemma: String,
        language: VocabularyLanguageID,
        frequencyProvenance: VocabularyFrequencyProvenance
    ) {
        let appleLanguage = language.appleNaturalLanguage
        var updatedRecords: [StoredWebWordRecord] = []
        for index in storedWebWordRecords.indices {
            let matchingVocabularyID = vocabularyID.map { storedWebWordRecords[index].vocabularyID == $0 } ?? false
            let matchingWord = GermanLemmaResolver.groupingKey(
                word: storedWebWordRecords[index].word,
                lemma: storedWebWordRecords[index].lemma,
                language: appleLanguage
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
                if metadata.frequency != nil {
                    storedWebWordRecords[index].dictionaryFrequencyProvenance = frequencyProvenance
                }
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
