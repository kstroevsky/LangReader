import Cocoa
import PDFKit
import LeafReaderCore

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

private final class PDFVocabularySaveMaterialization {
    let word: String
    let lemma: String
    let selectedRecord: StoredPDFWordRecord
    let matches: [PDFVocabularyPageMatch]
    let documentID: String
    let document: PDFDocument
    let startedAt: Date
    let startedUptime: TimeInterval
    var nextMatchIndex = 0
    var knownKeys: Set<String>
    var foundKeys: Set<String> = []
    var newRecords: [StoredPDFWordRecord] = []

    init(
        word: String,
        lemma: String,
        selectedRecord: StoredPDFWordRecord,
        matches: [PDFVocabularyPageMatch],
        documentID: String,
        document: PDFDocument,
        knownKeys: Set<String>,
        startedAt: Date
    ) {
        self.word = word
        self.lemma = lemma
        self.selectedRecord = selectedRecord
        self.matches = matches
        self.documentID = documentID
        self.document = document
        self.knownKeys = knownKeys
        self.startedAt = startedAt
        startedUptime = ProcessInfo.processInfo.systemUptime
    }
}

private final class PDFVocabularyBackfillMaterialization {
    let groupsByKey: [String: PDFVocabularyLemmaGroup]
    let matches: [PDFVocabularyGroupedPageMatch]
    let documentID: String
    let document: PDFDocument
    var nextMatchIndex = 0
    var knownKeys: Set<String>
    var newRecords: [StoredPDFWordRecord] = []

    init(
        groupsByKey: [String: PDFVocabularyLemmaGroup],
        matches: [PDFVocabularyGroupedPageMatch],
        documentID: String,
        document: PDFDocument,
        knownKeys: Set<String>
    ) {
        self.groupsByKey = groupsByKey
        self.matches = matches
        self.documentID = documentID
        self.document = document
        self.knownKeys = knownKeys
    }
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
        ensurePDFVocabularyIndex(language: language) { [weak self] snapshot, index in
            guard let self,
                  self.vocabularyState.occurrenceSearchID == searchID,
                  self.currentFileMD5 == documentID else { return }
            guard let snapshot, let index else {
                self.vocabularyState.occurrenceSearchID = nil
                return
            }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let lemmasByKey = Dictionary(uniqueKeysWithValues: groups.map { ($0.key, $0.lemma) })
                let groupedMatches = index.matches(lemmasByKey: lemmasByKey)
                let matches = groupedMatches.enumerated().flatMap { pageIndex, groups in
                    groups.flatMap { groupKey, occurrences in
                        occurrences.map {
                            PDFVocabularyGroupedPageMatch(
                                groupKey: groupKey,
                                pageMatch: PDFVocabularyPageMatch(
                                    pageIndex: pageIndex,
                                    text: snapshot.pageTexts[pageIndex],
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
        guard let store = pdfWordRecordStore,
              let documentID = currentFileMD5 else { return }
        let groupsByKey = Dictionary(uniqueKeysWithValues: groups.map { ($0.key, $0) })
        let knownKeys = Set(storedWordRecords.map {
            store.recordKey(pageIndex: $0.pageIndex, bounds: $0.bounds.cgRect)
        })
        continueBackfillingPDFVocabularyOccurrences(PDFVocabularyBackfillMaterialization(
            groupsByKey: groupsByKey,
            matches: matches,
            documentID: documentID,
            document: document,
            knownKeys: knownKeys
        ))
    }

    private func continueBackfillingPDFVocabularyOccurrences(
        _ state: PDFVocabularyBackfillMaterialization
    ) {
        guard currentDocumentKind == .pdf,
              currentFileMD5 == state.documentID,
              pdfView.document === state.document,
              let store = pdfWordRecordStore else { return }
        let endIndex = min(state.nextMatchIndex + 12, state.matches.count)
        if state.nextMatchIndex < endIndex {
            for match in state.matches[state.nextMatchIndex..<endIndex] {
                guard let group = state.groupsByKey[match.groupKey],
                      let page = state.document.page(at: match.pageMatch.pageIndex),
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
                let key = store.recordKey(pageIndex: record.pageIndex, bounds: record.bounds.cgRect)
                guard state.knownKeys.insert(key).inserted else { continue }
                state.newRecords.append(record)
            }
            state.nextMatchIndex = endIndex
        }
        guard state.nextMatchIndex >= state.matches.count else {
            DispatchQueue.main.async { [weak self] in
                self?.continueBackfillingPDFVocabularyOccurrences(state)
            }
            return
        }
        guard !state.newRecords.isEmpty,
              store.upsert(state.newRecords) else { return }
        storedWordRecords.append(contentsOf: state.newRecords)
        addStoredWordAnnotations(state.newRecords, refineBounds: false)
        refreshVocabularyPanelAfterLocalSave()
    }

    func saveCurrentPDFVocabularySelection() {
        let acknowledgementStartedAt = ProcessInfo.processInfo.systemUptime
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

        guard let documentID = currentFileMD5,
              let store = pdfWordRecordStore,
              store.upsert(selectedRecord) else {
            selectionActionToolbar.showSaveFailure()
            NSSound.beep()
            return
        }

        storedWordRecords.append(selectedRecord)
        addStoredWordAnnotation(selectedRecord, refineBounds: false)
        refreshVocabularyPanelAfterLocalSave()
        backfillDictionaryAnswerAsync(vocabularyID: selectedRecord.vocabularyID, word: word)
        selectionActionToolbar.showSaveResult(found: 1, inserted: 1)
        ReaderPerformance.record(
            .vocabularySaveAcknowledgement,
            milliseconds: (ProcessInfo.processInfo.systemUptime - acknowledgementStartedAt) * 1000
        )
        recordPersonalVocabularyQuery(word)

        let searchID = UUID()
        vocabularyState.occurrenceSearchID = searchID
        let saveStartedAt = Date()
        ensurePDFVocabularyIndex(language: language) { [weak self] snapshot, index in
            guard let self,
                  self.vocabularyState.occurrenceSearchID == searchID,
                  self.currentFileMD5 == documentID else { return }
            guard let snapshot, let index else {
                self.vocabularyState.occurrenceSearchID = nil
                return
            }
            let snapshotsReadyAt = Date()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let perPage = index.matches(lemma: lemma, selectedForm: word)
                let scanFinishedAt = Date()
                let queryMilliseconds = scanFinishedAt.timeIntervalSince(snapshotsReadyAt) * 1000
                NSLog(
                    "LeafVocabulary save timing: snapshots=%.0fms scan=%.0fms pages=%d",
                    snapshotsReadyAt.timeIntervalSince(saveStartedAt) * 1000,
                    scanFinishedAt.timeIntervalSince(snapshotsReadyAt) * 1000,
                    snapshot.pageTexts.count
                )
                let matches = perPage.enumerated().flatMap { pageIndex, occurrences in
                    occurrences.map {
                        PDFVocabularyPageMatch(
                            pageIndex: pageIndex,
                            text: snapshot.pageTexts[pageIndex],
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
                    ReaderPerformance.record(.vocabularyOccurrenceQuery, milliseconds: queryMilliseconds)
                    self.finishSavingAllPDFVocabularyOccurrences(
                        word: word,
                        lemma: lemma,
                        selectedRecord: selectedRecord,
                        matches: matches,
                        document: document,
                        documentID: documentID,
                        saveStartedAt: saveStartedAt
                    )
                }
            }
        }
    }

    private func finishSavingAllPDFVocabularyOccurrences(
        word: String,
        lemma: String,
        selectedRecord: StoredPDFWordRecord,
        matches: [PDFVocabularyPageMatch],
        document: PDFDocument,
        documentID: String,
        saveStartedAt: Date
    ) {
        vocabularyState.occurrenceSearchID = nil
        guard let store = pdfWordRecordStore else {
            // The selected occurrence was already committed before discovery
            // began. A cancelled document transition must not turn that durable
            // save into a visible failure.
            return
        }

        let knownKeys = Set(storedWordRecords.map {
            store.recordKey(pageIndex: $0.pageIndex, bounds: $0.bounds.cgRect)
        })
        continueSavingPDFVocabularyOccurrences(PDFVocabularySaveMaterialization(
            word: word,
            lemma: lemma,
            selectedRecord: selectedRecord,
            matches: matches,
            documentID: documentID,
            document: document,
            knownKeys: knownKeys,
            startedAt: saveStartedAt
        ))
    }

    private func continueSavingPDFVocabularyOccurrences(_ state: PDFVocabularySaveMaterialization) {
        guard currentDocumentKind == .pdf,
              currentFileMD5 == state.documentID,
              pdfView.document === state.document,
              let store = pdfWordRecordStore else { return }

        func appendIfNeeded(_ record: StoredPDFWordRecord) {
            let key = store.recordKey(pageIndex: record.pageIndex, bounds: record.bounds.cgRect)
            guard state.foundKeys.insert(key).inserted else { return }
            guard state.knownKeys.insert(key).inserted else { return }
            state.newRecords.append(record)
        }

        let endIndex = min(state.nextMatchIndex + 12, state.matches.count)
        if state.nextMatchIndex < endIndex {
            for match in state.matches[state.nextMatchIndex..<endIndex] {
                guard let page = state.document.page(at: match.pageIndex),
                      let selection = page.selection(for: match.occurrence.range) else { continue }
                let matchedText = VocabularyTextPolicy.normalizedOccurrenceText(
                    match.occurrence.matchedText,
                    matching: state.word
                )
                guard let record = storedPDFVocabularyRecord(
                    selection: selection,
                    word: state.word,
                    lemma: state.lemma,
                    surfaceForm: matchedText,
                    vocabularyID: state.selectedRecord.vocabularyID,
                    sourceText: match.text,
                    matchedText: matchedText,
                    sourceRange: match.occurrence.range
                ) else { continue }
                appendIfNeeded(record)
            }
            state.nextMatchIndex = endIndex
        }

        guard state.nextMatchIndex >= state.matches.count else {
            DispatchQueue.main.async { [weak self] in
                self?.continueSavingPDFVocabularyOccurrences(state)
            }
            return
        }

        appendIfNeeded(state.selectedRecord)
        defer {
            let persistenceMilliseconds = (ProcessInfo.processInfo.systemUptime - state.startedUptime) * 1000
            ReaderPerformance.record(.vocabularyOccurrencePersistence, milliseconds: persistenceMilliseconds)
            NSLog(
                "LeafVocabulary save timing: persist=%.0fms total=%.0fms matches=%d",
                persistenceMilliseconds,
                Date().timeIntervalSince(state.startedAt) * 1000,
                state.matches.count
            )
        }
        guard state.newRecords.isEmpty || store.upsert(state.newRecords) else {
            // Keep the immediate selected-word acknowledgement. Discovery is
            // additive and can be retried by a later backfill.
            selectionActionToolbar.showSaveResult(found: 1, inserted: 1)
            return
        }
        storedWordRecords.append(contentsOf: state.newRecords)
        addStoredWordAnnotations(state.newRecords, refineBounds: false)
        refreshVocabularyPanelAfterLocalSave()
        selectionActionToolbar.showSaveResult(
            found: state.foundKeys.count,
            inserted: state.newRecords.count + 1
        )
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
