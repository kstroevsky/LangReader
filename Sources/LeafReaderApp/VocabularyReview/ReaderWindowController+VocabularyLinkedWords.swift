import Foundation
import LeafReaderCore

extension ReaderWindowController {
    func updateStoredLinkedWordAnswer(linkID: String, question: String, answer: String) {
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAnswer.isEmpty else {
            if pendingPDFWordRecords[linkID] != nil {
                discardPendingWordAnnotations()
            }
            pendingPDFWordRecords.removeValue(forKey: linkID)
            pendingWebWordRecords.removeValue(forKey: linkID)
            return
        }

        if let index = storedWordRecords.firstIndex(where: { $0.id == linkID }) {
            let target = storedWordRecords[index]
            let key = VocabularyTextPolicy.canonicalVocabularyKey(target.word)
            var updated: [StoredPDFWordRecord] = []
            for recordIndex in storedWordRecords.indices where
                storedWordRecords[recordIndex].vocabularyID == target.vocabularyID
                    || VocabularyTextPolicy.canonicalVocabularyKey(storedWordRecords[recordIndex].word) == key {
                storedWordRecords[recordIndex].question = question
                storedWordRecords[recordIndex].answer = trimmedAnswer
                updated.append(storedWordRecords[recordIndex])
            }
            if pdfWordRecordStore?.upsert(updated) != true {
                saveStoredWordRecords()
            }
            return
        }
        if let index = storedWebWordRecords.firstIndex(where: { $0.id == linkID }) {
            let target = storedWebWordRecords[index]
            let targetKey = target.vocabularyID
                ?? GermanLemmaResolver.groupingKey(
                    word: target.word,
                    lemma: target.lemma,
                    language: vocabularyDocumentLanguage
                )
            for recordIndex in storedWebWordRecords.indices {
                let record = storedWebWordRecords[recordIndex]
                let recordKey = record.vocabularyID
                    ?? GermanLemmaResolver.groupingKey(
                        word: record.word,
                        lemma: record.lemma,
                        language: vocabularyDocumentLanguage
                    )
                guard recordKey == targetKey else { continue }
                storedWebWordRecords[recordIndex].question = question
                storedWebWordRecords[recordIndex].answer = trimmedAnswer
                saveStoredWebWordRecord(storedWebWordRecords[recordIndex])
            }
            return
        }

        if let pending = pendingPDFWordRecords.removeValue(forKey: linkID) {
            let record = StoredPDFWordRecord(
                id: pending.id,
                vocabularyID: pending.vocabularyID,
                word: pending.word,
                pageIndex: pending.pageIndex,
                bounds: pending.bounds,
                context: pending.context,
                question: question,
                answer: trimmedAnswer,
                dictionaryTags: pending.dictionaryTags,
                dictionaryFrequency: pending.dictionaryFrequency,
                createdAt: pending.createdAt,
                srs: VocabularySRSState.initial(createdAt: pending.createdAt)
            )
            storedWordRecords.append(record)
            addStoredWordAnnotation(record)
            saveStoredWordRecord(record)
            return
        }

        if let pending = pendingWebWordRecords.removeValue(forKey: linkID) {
            let record = StoredWebWordRecord(
                id: pending.id,
                vocabularyID: pending.vocabularyID,
                word: pending.word,
                lemma: pending.lemma,
                surfaceForm: pending.surfaceForm,
                context: pending.context,
                occurrenceIndex: pending.occurrenceIndex,
                scrollProgress: pending.scrollProgress,
                question: question,
                answer: trimmedAnswer,
                dictionaryTags: pending.dictionaryTags,
                dictionaryFrequency: pending.dictionaryFrequency,
                createdAt: pending.createdAt,
                srs: VocabularySRSState.initial(createdAt: pending.createdAt)
            )
            storedWebWordRecords.append(record)
            saveStoredWebWordRecord(record)
        }
    }

    func discardPendingLinkedWord(linkID: String) {
        if pendingPDFWordRecords.removeValue(forKey: linkID) != nil {
            discardPendingWordAnnotations()
        }
        if pendingWebWordRecords.removeValue(forKey: linkID) != nil {
            removeWebWordHighlight(id: linkID)
        }
    }

    func linkedWordAnswer(for linkID: String) -> String? {
        if let record = storedWordRecords.first(where: { $0.id == linkID }) {
            return record.answer
        }
        if let record = storedWebWordRecords.first(where: { $0.id == linkID }) {
            return record.answer
        }
        return nil
    }

    func reusablePDFWordRecord(for word: String) -> StoredPDFWordRecord? {
        let normalized = normalizedVocabularyKey(word)
        return storedWordRecords.first {
            normalizedVocabularyKey($0.word) == normalized && !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func reusableWebWordRecord(for word: String) -> StoredWebWordRecord? {
        let language = vocabularyDocumentLanguage
        let key = GermanLemmaResolver.groupingKey(word: word, language: language)
        return storedWebWordRecords.first {
            GermanLemmaResolver.groupingKey(word: $0.word, lemma: $0.lemma, language: language) == key
                && !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func existingWebVocabularyID(for word: String, lemma: String? = nil) -> String? {
        let language = vocabularyDocumentLanguage
        let key = GermanLemmaResolver.groupingKey(word: word, lemma: lemma, language: language)
        return storedWebWordRecords.first {
            GermanLemmaResolver.groupingKey(word: $0.word, lemma: $0.lemma, language: language) == key
        }?.vocabularyID
    }

    func normalizedVocabularyKey(_ word: String) -> String {
        word
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
