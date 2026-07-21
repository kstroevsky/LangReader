import Cocoa

struct VocabularyRecordMutationResult {
    let didUpdatePDF: Bool
    let didUpdateWeb: Bool

    var didUpdate: Bool {
        didUpdatePDF || didUpdateWeb
    }
}

extension ReaderWindowController {
    func loadStoredWordRecords() -> [StoredPDFWordRecord] {
        guard let store = pdfWordRecordStore else { return [] }
        let records = store.load()
        var repairedWords: [String: String] = [:]
        for record in records {
            guard let candidate = VocabularyTextPolicy.dehyphenatedPDFLayoutCandidate(word: record.word, context: record.context),
                  hasLocalSpellingEntry(candidate),
                  !hasLocalSpellingEntry(record.word) else { continue }
            let key = record.vocabularyID ?? VocabularyTextPolicy.canonicalVocabularyKey(record.word)
            repairedWords[key] = candidate
        }

        var didRepair = false
        let repairedRecords = records.map { record -> StoredPDFWordRecord in
            var repairedRecord = record
            let key = record.vocabularyID ?? VocabularyTextPolicy.canonicalVocabularyKey(record.word)
            let surfaceForm = VocabularyExporter.nonEmptyText(record.surfaceForm) ?? record.word
            if repairedRecord.surfaceForm != surfaceForm {
                repairedRecord.surfaceForm = surfaceForm
                didRepair = true
            }
            let lemma = VocabularyExporter.nonEmptyText(record.lemma)
                ?? GermanLemmaResolver.lemma(for: surfaceForm, language: vocabularyDocumentLanguage)
            if repairedRecord.lemma != lemma {
                repairedRecord.lemma = lemma
                didRepair = true
            }
            if let repairedWord = repairedWords[key], repairedWord != repairedRecord.word {
                repairedRecord.word = repairedWord
                repairedRecord.surfaceForm = repairedWord
                repairedRecord.lemma = GermanLemmaResolver.lemma(for: repairedWord, language: vocabularyDocumentLanguage)
                didRepair = true
            }
            if let context = repairedRecord.context {
                let repairedContext = normalizedPDFVocabularyContext(context)
                if repairedContext != context {
                    repairedRecord.context = repairedContext
                    didRepair = true
                }
            }
            if let refreshedContext = VocabularyContextProvider.replacementPDFContextIfNeeded(
                for: repairedRecord,
                document: pdfView.document
            ) {
                let normalizedContext = normalizedPDFVocabularyContext(refreshedContext)
                if normalizedContext != repairedRecord.context {
                    repairedRecord.context = normalizedContext
                    didRepair = true
                }
            }
            return repairedRecord
        }

        // Drop occurrences the pre-fix recognizer mis-filed, which new scans no
        // longer produce. Two narrow candidate classes, each confirmed by a
        // group-membership re-scan of the record's own context so nothing the
        // fixed matcher still produces is ever removed:
        //   1. hyphenated line-break fragments — a surface that never stands as a
        //      whole word in its context ("folg" carved out of "Er-\nfolg");
        //   2. case-folded homographs — a surface that folds to the group key but
        //      is spelled with different case, i.e. the noun "Folgen" (lemma
        //      "Folge") swept into the verb group "folgen".
        // The gates deliberately never look at differently-keyed inflections
        // ("folgende", "folgt"), so those legitimate forms are always kept; and
        // same-line compound constituents ("Abteilung" in "IT-Abteilung") survive
        // because the group re-scan still reproduces them.
        let staleIDs = Set(repairedRecords.filter { record in
            let surface = record.occurrenceSurfaceForm
            let context = record.context ?? ""
            let groupLemma = record.vocabularyGroupingText
            let isLineWrapFragment = VocabularyTextPolicy.surfaceOccursOnlyWithinLargerWord(
                surface: surface, context: context
            )
            let isCaseFoldedHomograph =
                VocabularyTextPolicy.canonicalVocabularyKey(surface)
                    == VocabularyTextPolicy.canonicalVocabularyKey(groupLemma)
                && !VocabularyTextPolicy.surfaceMatchesLemmaExactly(surface, groupLemma)
            guard isLineWrapFragment || isCaseFoldedHomograph else { return false }
            return !GermanLemmaOccurrenceMatcher.groupReproducesOccurrence(
                surfaceForm: surface,
                groupLemma: groupLemma,
                in: context,
                language: vocabularyDocumentLanguage
            )
        }.map(\.id))
        let cleanedRecords = repairedRecords.filter { !staleIDs.contains($0.id) }
        if !staleIDs.isEmpty {
            NSLog("LeafVocabulary: pruned %d mis-filed occurrence(s) on load", staleIDs.count)
        }

        guard didRepair || !staleIDs.isEmpty else { return cleanedRecords }

        store.save(cleanedRecords)
        DispatchQueue.main.async { [weak self] in
            self?.backfillStoredGermanLemmaOccurrences()
        }
        return cleanedRecords
    }

    func saveStoredWordRecords() {
        scheduleStoredWordRecordsSave()
    }

    func saveStoredWordRecord(_ record: StoredPDFWordRecord) {
        if pdfWordRecordStore?.upsert(record) != true {
            saveStoredWordRecords()
        }
    }

    func loadStoredWebWordRecords() -> [StoredWebWordRecord] {
        webWordRecordStore?.load() ?? []
    }

    func saveStoredWebWordRecords() {
        scheduleStoredWebWordRecordsSave()
    }

    func saveStoredWebWordRecord(_ record: StoredWebWordRecord) {
        if webWordRecordStore?.upsert(record) != true {
            saveStoredWebWordRecords()
        }
    }

    func deleteStoredWordRecords(ids: [String]) {
        if pdfWordRecordStore?.delete(ids: ids) != true {
            saveStoredWordRecords()
        }
    }

    func deleteStoredWebWordRecords(ids: [String]) {
        if webWordRecordStore?.delete(ids: ids) != true {
            saveStoredWebWordRecords()
        }
    }

    @discardableResult
    func updateStoredVocabularyRecords(
        ids: Set<String>,
        updatePDF: (inout StoredPDFWordRecord) -> Bool,
        updateWeb: (inout StoredWebWordRecord) -> Bool
    ) -> VocabularyRecordMutationResult {
        var didUpdatePDF = false
        for index in storedWordRecords.indices where ids.contains(storedWordRecords[index].id) {
            guard updatePDF(&storedWordRecords[index]) else { continue }
            saveStoredWordRecord(storedWordRecords[index])
            didUpdatePDF = true
        }
        if didUpdatePDF {
            saveStoredWordRecords()
        }

        var didUpdateWeb = false
        for index in storedWebWordRecords.indices where ids.contains(storedWebWordRecords[index].id) {
            guard updateWeb(&storedWebWordRecords[index]) else { continue }
            saveStoredWebWordRecord(storedWebWordRecords[index])
            didUpdateWeb = true
        }
        if didUpdateWeb {
            saveStoredWebWordRecords()
        }

        return VocabularyRecordMutationResult(didUpdatePDF: didUpdatePDF, didUpdateWeb: didUpdateWeb)
    }

    func scheduleStoredWordRecordsSave() {
        pdfWordRecordsSaveTask.schedule { [weak self] in
            self?.flushStoredWordRecordsSave()
        }
    }

    func scheduleStoredWebWordRecordsSave() {
        webWordRecordsSaveTask.schedule { [weak self] in
            self?.flushStoredWebWordRecordsSave()
        }
    }

    func flushStoredWordRecordsSave() {
        pdfWordRecordsSaveTask.cancel()
        pdfWordRecordStore?.save(storedWordRecords)
    }

    func flushStoredWebWordRecordsSave() {
        webWordRecordsSaveTask.cancel()
        webWordRecordStore?.save(storedWebWordRecords)
    }

    func flushCurrentBookWordRecordSaves() {
        flushStoredWordRecordsSave()
        flushStoredWebWordRecordsSave()
    }
}
