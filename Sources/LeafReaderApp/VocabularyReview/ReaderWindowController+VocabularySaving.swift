import Cocoa
import PDFKit
import LeafReaderCore

private struct PDFVocabularyPageSnapshot: Sendable {
    let pageIndex: Int
    let text: String
}

private struct PDFVocabularyPageMatch: Sendable {
    let pageIndex: Int
    let text: String
    let occurrence: VocabularyTextOccurrence
}

private struct PDFVocabularyLemmaGroup: Sendable {
    let key: String
    let word: String
    let lemma: String
    let vocabularyID: String
}

private struct PDFVocabularyGroupedPageMatch: Sendable {
    let groupKey: String
    let pageMatch: PDFVocabularyPageMatch
}

extension ReaderWindowController {
    /// Detects and caches the language this document's vocabulary is grouped by,
    /// from a sample of its first pages. Must run before any occurrence scanning
    /// or lemma grouping so every grouping key uses the same language.
    func updateVocabularyDocumentLanguage() {
        if currentDocumentKind == .pdf, let document = pdfView.document {
            vocabularyDocumentLanguage = VocabularyLanguageDetector.language(
                pageCount: document.pageCount,
                pageText: { document.page(at: $0)?.string }
            )
            return
        }
        // Web and EPUB documents have no page text to sample here, so the
        // contexts saved with their words stand in. This must still run for
        // them: leaving the previous document's language in place would
        // lemmatize an English article with, say, German grammar.
        vocabularyDocumentLanguage = VocabularyLanguageDetector.language(
            forContexts: storedWebWordRecords.map(\.context)
        )
    }

    func backfillStoredGermanLemmaOccurrences() {
        var seenKeys = Set<String>()
        let groups = storedWordRecords
            .sorted { $0.createdAt < $1.createdAt }
            .compactMap { record -> PDFVocabularyLemmaGroup? in
                let lemma = VocabularyExporter.nonEmptyText(record.lemma)
                    ?? GermanLemmaResolver.lemma(for: record.occurrenceSurfaceForm, language: vocabularyDocumentLanguage)
                let key = GermanLemmaResolver.groupingKey(word: record.word, lemma: lemma, language: vocabularyDocumentLanguage)
                guard !key.isEmpty,
                      seenKeys.insert(key).inserted,
                      let vocabularyID = record.vocabularyID else { return nil }
                return PDFVocabularyLemmaGroup(
                    key: key,
                    word: record.word,
                    lemma: lemma,
                    vocabularyID: vocabularyID
                )
            }
        backfillGermanLemmaOccurrences(groups)
    }

    func backfillGermanLemmaOccurrences(word: String, lemma: String, vocabularyID: String?) {
        guard let vocabularyID else { return }
        let key = GermanLemmaResolver.groupingKey(word: word, lemma: lemma, language: vocabularyDocumentLanguage)
        guard !key.isEmpty else { return }
        backfillGermanLemmaOccurrences([
            PDFVocabularyLemmaGroup(key: key, word: word, lemma: lemma, vocabularyID: vocabularyID)
        ])
    }

    private func backfillGermanLemmaOccurrences(_ groups: [PDFVocabularyLemmaGroup]) {
        guard currentDocumentKind == .pdf,
              !groups.isEmpty,
              let documentID = currentFileMD5,
              pdfView.document != nil else { return }

        let searchID = UUID()
        let language = vocabularyDocumentLanguage
        vocabularyState.occurrenceSearchID = searchID
        collectPDFVocabularyPageSnapshots(documentID: documentID, searchID: searchID) { [weak self] snapshots in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let lemmasByKey = Dictionary(uniqueKeysWithValues: groups.map { ($0.key, $0.lemma) })
                let matches = snapshots.flatMap { snapshot in
                    GermanLemmaOccurrenceMatcher.matches(
                        lemmasByKey: lemmasByKey,
                        in: snapshot.text,
                        language: language
                    ).flatMap { groupKey, occurrences in
                        occurrences.map {
                            PDFVocabularyGroupedPageMatch(
                                groupKey: groupKey,
                                pageMatch: PDFVocabularyPageMatch(
                                    pageIndex: snapshot.pageIndex,
                                    text: snapshot.text,
                                    occurrence: $0
                                )
                            )
                        }
                    }
                }
                DispatchQueue.main.async {
                    guard let self,
                          self.vocabularyState.occurrenceSearchID == searchID,
                          self.currentFileMD5 == documentID,
                          let document = self.pdfView.document else { return }
                    self.finishBackfillingGermanLemmaOccurrences(
                        groups: groups,
                        matches: matches,
                        document: document
                    )
                }
            }
        }
    }

    private func finishBackfillingGermanLemmaOccurrences(
        groups: [PDFVocabularyLemmaGroup],
        matches: [PDFVocabularyGroupedPageMatch],
        document: PDFDocument
    ) {
        vocabularyState.occurrenceSearchID = nil
        guard let store = pdfWordRecordStore else { return }
        let groupsByKey = Dictionary(uniqueKeysWithValues: groups.map { ($0.key, $0) })
        var knownKeys = Set(storedWordRecords.map {
            store.recordKey(pageIndex: $0.pageIndex, bounds: $0.bounds.cgRect)
        })
        var newRecords: [StoredPDFWordRecord] = []

        for match in matches {
            guard let group = groupsByKey[match.groupKey],
                  let page = document.page(at: match.pageMatch.pageIndex),
                  let selection = page.selection(for: match.pageMatch.occurrence.range) else { continue }
            let matchedText = VocabularyTextPolicy.normalizedOccurrenceText(
                match.pageMatch.occurrence.matchedText,
                matching: group.word
            )
            guard let record = storedPDFVocabularyRecord(
                selection: selection,
                word: group.word,
                lemma: group.lemma,
                surfaceForm: matchedText,
                vocabularyID: group.vocabularyID,
                sourceText: match.pageMatch.text,
                matchedText: matchedText,
                sourceRange: match.pageMatch.occurrence.range
            ) else { continue }
            let locationKey = store.recordKey(pageIndex: record.pageIndex, bounds: record.bounds.cgRect)
            guard knownKeys.insert(locationKey).inserted else { continue }
            newRecords.append(record)
        }

        guard !newRecords.isEmpty,
              store.upsert(newRecords) else { return }
        storedWordRecords.append(contentsOf: newRecords)
        for record in newRecords {
            addStoredWordAnnotation(record)
        }
        refreshVocabularyPanelAfterLocalSave()
    }

    func saveCurrentPDFVocabularySelection() {
        guard currentDocumentKind == .pdf,
              pdfView.document != nil,
              let selection = pdfView.currentSelection else {
            NSSound.beep()
            return
        }
        let fallback = selectedReaderTextForToolbar()
        let word = vocabularyTextForCurrentPDFSelection(selection: selection, fallback: fallback)
        guard VocabularyTextPolicy.isVocabularySelection(word) else {
            NSSound.beep()
            return
        }
        let language = vocabularyDocumentLanguage
        let lemma = GermanLemmaResolver.lemma(for: word, language: language)

        if removeCurrentPDFVocabularySelectionIfSaved(word, lemma: lemma) {
            return
        }

        guard let selectedRecord = storedPDFVocabularyRecord(selection: selection, word: word, lemma: lemma, surfaceForm: word) else {
            NSSound.beep()
            return
        }

        let searchID = UUID()
        guard let documentID = currentFileMD5 else { return }
        vocabularyState.occurrenceSearchID = searchID
        selectionActionToolbar.showSaveInProgress()
        recordPersonalVocabularyQuery(word)

        let saveStartedAt = Date()
        collectPDFVocabularyPageSnapshots(documentID: documentID, searchID: searchID) { [weak self] snapshots in
            let snapshotsReadyAt = Date()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let perPage = GermanLemmaOccurrenceMatcher.matches(
                    lemma: lemma,
                    selectedForm: word,
                    inTexts: snapshots.map(\.text),
                    language: language
                )
                let scanFinishedAt = Date()
                NSLog(
                    "LeafVocabulary save timing: snapshots=%.0fms scan=%.0fms pages=%d",
                    snapshotsReadyAt.timeIntervalSince(saveStartedAt) * 1000,
                    scanFinishedAt.timeIntervalSince(snapshotsReadyAt) * 1000,
                    snapshots.count
                )
                let matches = zip(snapshots, perPage).flatMap { snapshot, occurrences in
                    occurrences.map {
                        PDFVocabularyPageMatch(
                            pageIndex: snapshot.pageIndex,
                            text: snapshot.text,
                            occurrence: $0
                        )
                    }
                }
                DispatchQueue.main.async {
                    guard let self,
                          self.vocabularyState.occurrenceSearchID == searchID,
                          self.currentFileMD5 == documentID,
                          let document = self.pdfView.document else {
                        return
                    }
                    let persistStartedAt = Date()
                    defer {
                        NSLog(
                            "LeafVocabulary save timing: persist=%.0fms total=%.0fms matches=%d",
                            Date().timeIntervalSince(persistStartedAt) * 1000,
                            Date().timeIntervalSince(saveStartedAt) * 1000,
                            matches.count
                        )
                    }
                    self.finishSavingAllPDFVocabularyOccurrences(
                        word: word,
                        lemma: lemma,
                        selectedRecord: selectedRecord,
                        matches: matches,
                        document: document
                    )
                }
            }
        }
    }

    private func collectPDFVocabularyPageSnapshots(
        documentID: String,
        searchID: UUID,
        pageIndex: Int = 0,
        snapshots: [PDFVocabularyPageSnapshot] = [],
        completion: @escaping ([PDFVocabularyPageSnapshot]) -> Void
    ) {
        guard vocabularyState.occurrenceSearchID == searchID,
              currentFileMD5 == documentID,
              let document = pdfView.document else {
            return
        }

        var collected = snapshots
        let nextPageIndex = min(pageIndex + 12, document.pageCount)
        for index in pageIndex..<nextPageIndex {
            guard let text = document.page(at: index)?.string, !text.isEmpty else { continue }
            collected.append(PDFVocabularyPageSnapshot(pageIndex: index, text: text))
        }

        guard nextPageIndex < document.pageCount else {
            completion(collected)
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.collectPDFVocabularyPageSnapshots(
                documentID: documentID,
                searchID: searchID,
                pageIndex: nextPageIndex,
                snapshots: collected,
                completion: completion
            )
        }
    }

    private func finishSavingAllPDFVocabularyOccurrences(
        word: String,
        lemma: String,
        selectedRecord: StoredPDFWordRecord,
        matches: [PDFVocabularyPageMatch],
        document: PDFDocument
    ) {
        vocabularyState.occurrenceSearchID = nil
        guard let store = pdfWordRecordStore else {
            selectionActionToolbar.showSaveFailure()
            NSSound.beep()
            return
        }

        var knownKeys = Set(storedWordRecords.map {
            store.recordKey(pageIndex: $0.pageIndex, bounds: $0.bounds.cgRect)
        })
        var foundKeys = Set<String>()
        var newRecords: [StoredPDFWordRecord] = []

        func appendIfNeeded(_ record: StoredPDFWordRecord) {
            let key = store.recordKey(pageIndex: record.pageIndex, bounds: record.bounds.cgRect)
            guard !foundKeys.contains(key) else { return }
            foundKeys.insert(key)
            guard !knownKeys.contains(key) else { return }
            knownKeys.insert(key)
            newRecords.append(record)
        }

        for match in matches {
            guard let page = document.page(at: match.pageIndex),
                  let selection = page.selection(for: match.occurrence.range),
                  let record = storedPDFVocabularyRecord(
                    selection: selection,
                    word: word,
                    lemma: lemma,
                    surfaceForm: VocabularyTextPolicy.normalizedOccurrenceText(match.occurrence.matchedText, matching: word),
                    vocabularyID: selectedRecord.vocabularyID,
                    sourceText: match.text,
                    matchedText: VocabularyTextPolicy.normalizedOccurrenceText(match.occurrence.matchedText, matching: word),
                    sourceRange: match.occurrence.range
                  ) else {
                continue
            }
            appendIfNeeded(record)
        }
        appendIfNeeded(selectedRecord)

        guard store.upsert(newRecords) else {
            selectionActionToolbar.showSaveFailure()
            NSSound.beep()
            return
        }
        storedWordRecords.append(contentsOf: newRecords)
        for record in newRecords {
            addStoredWordAnnotation(record)
        }
        refreshVocabularyPanelAfterLocalSave()
        backfillDictionaryAnswerAsync(vocabularyID: selectedRecord.vocabularyID, word: word)
        selectionActionToolbar.showSaveResult(found: foundKeys.count, inserted: newRecords.count)
    }

    private func storedPDFVocabularyRecord(
        selection: PDFSelection,
        word: String,
        lemma: String? = nil,
        surfaceForm: String? = nil,
        vocabularyID: String? = nil,
        sourceText: String? = nil,
        matchedText: String? = nil,
        sourceRange: NSRange? = nil
    ) -> StoredPDFWordRecord? {
        guard let document = pdfView.document,
              let page = selection.pages.first else {
            return nil
        }
        let rawBounds = selection.bounds(for: page).insetBy(dx: -1.5, dy: -1)
        let bounds = precisePDFSelectionBounds(
            page: page,
            originalBounds: rawBounds,
            queryText: word
        ) ?? rawBounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let contextSource = sourceText ?? page.string ?? ""
        let selectedText = matchedText ?? selection.string ?? word
        let exactContext = sourceRange.flatMap {
            ReaderAIContextBuilder.selectedTextContext(
                occurrenceRange: $0,
                sourceText: contextSource,
                radius: 24
            )
        }
        let context = (exactContext ?? ReaderAIContextBuilder.selectedTextContext(
                selectedText: selectedText,
                sourceText: contextSource,
                radius: 24
            )).map {
            normalizedPDFVocabularyContext(ReaderAIContextBuilder.trimLeadingContextQuotes($0))
        } ?? ""
        let createdAt = Date()
        return StoredPDFWordRecord(
            id: UUID().uuidString,
            vocabularyID: vocabularyID ?? existingPDFVocabularyID(for: word, lemma: lemma) ?? UUID().uuidString,
            word: VocabularyTextPolicy.normalizedVocabularyText(word),
            lemma: lemma,
            surfaceForm: VocabularyTextPolicy.normalizedOccurrenceText(surfaceForm ?? word, matching: word),
            pageIndex: document.index(for: page),
            bounds: StoredPDFWordRect(bounds),
            context: context,
            question: "",
            answer: "",
            dictionaryTags: nil,
            dictionaryFrequency: nil,
            createdAt: createdAt,
            srs: VocabularySRSState.initial(createdAt: createdAt)
        )
    }

    func refreshVocabularyPanelAfterLocalSave() {
        vocabularyLibraryWindowController.scheduleReload()
        guard vocabularyPanelController.panel != nil else { return }
        currentVocabularyExportRecords = makeCurrentVocabularyExportRecords()
        scheduleVocabularyPanelReload()
    }

    func existingPDFVocabularyID(for word: String, lemma: String? = nil) -> String? {
        let language = vocabularyDocumentLanguage
        let key = GermanLemmaResolver.groupingKey(word: word, lemma: lemma, language: language)
        return storedWordRecords.first {
            GermanLemmaResolver.groupingKey(word: $0.word, lemma: $0.lemma, language: language) == key
        }?.vocabularyID
    }

    func isPDFVocabularySelectionSaved(_ word: String) -> Bool {
        let language = vocabularyDocumentLanguage
        let key = GermanLemmaResolver.groupingKey(word: word, language: language)
        return !key.isEmpty && storedWordRecords.contains {
            GermanLemmaResolver.groupingKey(word: $0.word, lemma: $0.lemma, language: language) == key
        }
    }

    private func removeCurrentPDFVocabularySelectionIfSaved(_ word: String, lemma: String) -> Bool {
        let language = vocabularyDocumentLanguage
        let key = GermanLemmaResolver.groupingKey(word: word, lemma: lemma, language: language)
        let ids = storedWordRecords.compactMap { record in
            GermanLemmaResolver.groupingKey(word: record.word, lemma: record.lemma, language: language) == key ? record.id : nil
        }
        guard !ids.isEmpty else { return false }

        removeVocabularyRecords(ids: ids)
        refreshVocabularyPanelAfterLocalSave()
        selectionActionToolbar.showRemoveResult(removed: ids.count)
        return true
    }
}
