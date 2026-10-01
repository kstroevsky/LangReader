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
            var proposedRecords = storedWordRecords
            var updated: [StoredPDFWordRecord] = []
            for recordIndex in proposedRecords.indices where
                proposedRecords[recordIndex].vocabularyID == target.vocabularyID
                    || VocabularyTextPolicy.canonicalVocabularyKey(proposedRecords[recordIndex].word) == key {
                proposedRecords[recordIndex].question = question
                proposedRecords[recordIndex].answer = trimmedAnswer
                updated.append(proposedRecords[recordIndex])
            }
            guard pdfWordRecordStore?.upsert(updated) == true else {
                NSLog("LeafReader vocabulary: failed to persist linked PDF vocabulary group")
                return
            }
            storedWordRecords = proposedRecords
            return
        }
        if let index = storedWebWordRecords.firstIndex(where: { $0.id == linkID }) {
            let target = storedWebWordRecords[index]
            let targetKey = target.vocabularyID
                ?? vocabularyGroupingKey(
                    word: target.word,
                    lemma: target.lemma,
                    language: target.language
                )
            var proposedRecords = storedWebWordRecords
            var changedRecords: [StoredWebWordRecord] = []
            for recordIndex in proposedRecords.indices {
                let record = proposedRecords[recordIndex]
                let recordKey = record.vocabularyID
                    ?? vocabularyGroupingKey(
                        word: record.word,
                        lemma: record.lemma,
                        language: record.language
                )
                guard recordKey == targetKey else { continue }
                proposedRecords[recordIndex].question = question
                proposedRecords[recordIndex].answer = trimmedAnswer
                changedRecords.append(proposedRecords[recordIndex])
            }
            guard let store = webWordRecordStore, store.upsert(changedRecords) else {
                NSLog("LeafReader vocabulary: failed to persist linked web vocabulary group")
                return
            }
            storedWebWordRecords = proposedRecords
            return
        }

        if let pending = pendingPDFWordRecords.removeValue(forKey: linkID) {
            let record = StoredPDFWordRecord(
                id: pending.id,
                vocabularyID: pending.vocabularyID,
                word: pending.word,
                language: pending.language,
                pageIndex: pending.pageIndex,
                bounds: pending.bounds,
                textAnchor: pending.textAnchor,
                context: pending.context,
                question: question,
                answer: trimmedAnswer,
                dictionaryTags: pending.dictionaryTags,
                dictionaryFrequency: pending.dictionaryFrequency,
                dictionaryFrequencyProvenance: pending.dictionaryFrequencyProvenance,
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
                language: pending.language,
                lemma: pending.lemma,
                surfaceForm: pending.surfaceForm,
                context: pending.context,
                occurrenceIndex: pending.occurrenceIndex,
                scrollProgress: pending.scrollProgress,
                question: question,
                answer: trimmedAnswer,
                dictionaryTags: pending.dictionaryTags,
                dictionaryFrequency: pending.dictionaryFrequency,
                dictionaryFrequencyProvenance: pending.dictionaryFrequencyProvenance,
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

    func vocabularyAnswer(for word: String, language: VocabularyLanguageID) -> String? {
        let normalized = normalizedVocabularyKey(word)
        let answer: String?
        if currentDocumentKind == .pdf {
            answer = storedWordRecords.first {
                ($0.language == nil || $0.language == language)
                    && normalizedVocabularyKey($0.word) == normalized
                    && !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }?.answer
        } else {
            let key = vocabularyGroupingKey(word: word, language: language)
            answer = storedWebWordRecords.first {
                ($0.language == nil || $0.language == language)
                    && vocabularyGroupingKey(
                        word: $0.word,
                        lemma: $0.lemma,
                        language: $0.language ?? language
                    ) == key
                    && !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }?.answer
        }
        let trimmed = answer?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    func reusablePDFWordRecord(for word: String) -> StoredPDFWordRecord? {
        let normalized = normalizedVocabularyKey(word)
        return storedWordRecords.first {
            normalizedVocabularyKey($0.word) == normalized && !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func reusableWebWordRecord(for word: String) -> StoredWebWordRecord? {
        let language = vocabularyDocumentLanguageID
        let key = vocabularyGroupingKey(word: word, language: language)
        return storedWebWordRecords.first {
            vocabularyGroupingKey(word: $0.word, lemma: $0.lemma, language: $0.language ?? language) == key
                && !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func existingWebVocabularyID(for word: String, lemma: String? = nil) -> String? {
        let language = vocabularyDocumentLanguageID
        let key = vocabularyGroupingKey(word: word, lemma: lemma, language: language)
        return storedWebWordRecords.first {
            vocabularyGroupingKey(word: $0.word, lemma: $0.lemma, language: $0.language ?? language) == key
        }?.vocabularyID
    }

    func normalizedVocabularyKey(_ word: String) -> String {
        word
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
