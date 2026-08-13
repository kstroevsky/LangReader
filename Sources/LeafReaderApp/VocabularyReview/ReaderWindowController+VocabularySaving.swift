import Cocoa
import NaturalLanguage
import PDFKit
import LeafReaderCore

private enum VocabularyOccurrencePersistence {
    static let queue = DispatchQueue(
        label: "com.linlu.leafreader.vocabulary-occurrence-persistence",
        qos: .utility
    )
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
    let existingRecordKeys: Set<String>
    let legacyGeometryPageIndexes: Set<Int>
    var candidateRecords: [StoredPDFWordRecord] = []

    init(
        word: String,
        lemma: String,
        selectedRecord: StoredPDFWordRecord,
        matches: [PDFVocabularyPageMatch],
        documentID: String,
        document: PDFDocument,
        existingRecordKeys: Set<String>,
        legacyGeometryPageIndexes: Set<Int>,
        startedAt: Date
    ) {
        self.word = word
        self.lemma = lemma
        self.selectedRecord = selectedRecord
        self.matches = matches
        self.documentID = documentID
        self.document = document
        self.existingRecordKeys = existingRecordKeys
        self.legacyGeometryPageIndexes = legacyGeometryPageIndexes
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
    let legacyGeometryPageIndexes: Set<Int>
    var newRecords: [StoredPDFWordRecord] = []

    init(
        groupsByKey: [String: PDFVocabularyLemmaGroup],
        matches: [PDFVocabularyGroupedPageMatch],
        documentID: String,
        document: PDFDocument,
        knownKeys: Set<String>,
        legacyGeometryPageIndexes: Set<Int>
    ) {
        self.groupsByKey = groupsByKey
        self.matches = matches
        self.documentID = documentID
        self.document = document
        self.knownKeys = knownKeys
        self.legacyGeometryPageIndexes = legacyGeometryPageIndexes
    }
}

extension ReaderWindowController {
    func saveCurrentVocabularySelection() {
        if currentDocumentKind == .pdf {
            saveCurrentPDFVocabularySelection()
        } else {
            saveCurrentWebVocabularySelection()
        }
    }

    func toggleFocusedVocabularyWord(word: String, answer: String) {
        if removeVocabularyWordIfSaved(word) {
            return
        }
        if currentDocumentKind == .pdf {
            saveCurrentPDFVocabularySelection(preferredWord: word, definitionAnswer: answer)
        } else {
            saveCurrentWebVocabularySelection(preferredWord: word, definitionAnswer: answer)
        }
    }

    func saveCurrentWebVocabularySelection(
        preferredWord: String? = nil,
        definitionAnswer: String? = nil
    ) {
        guard currentDocumentKind != .pdf,
              let store = webWordRecordStore else {
            NSSound.beep()
            return
        }

        let selectedWord = VocabularyTextPolicy.normalizedVocabularyText(selectedReaderTextForToolbar())
        let word = VocabularyTextPolicy.normalizedVocabularyText(preferredWord ?? selectedWord)
        guard VocabularyTextPolicy.isVocabularySelection(word) else {
            NSSound.beep()
            return
        }
        let language = vocabularyDocumentLanguage
        let lemma = GermanLemmaResolver.lemma(for: word, language: language)
        let requestedKey = GermanLemmaResolver.groupingKey(word: word, lemma: lemma, language: language)
        if preferredWord != nil, !selectedWord.isEmpty {
            let selectedKey = GermanLemmaResolver.groupingKey(word: selectedWord, language: language)
            guard selectedKey == requestedKey else {
                NSSound.beep()
                return
            }
        }

        if removeVocabularyWordIfSaved(word) {
            return
        }

        let createdAt = Date()
        let id = UUID().uuidString
        let answer = definitionAnswer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let context = ReaderAIContextBuilder.trimLeadingContextQuotes(selectionState.webSelectionContext)
        let record = StoredWebWordRecord(
            id: id,
            vocabularyID: existingWebVocabularyID(for: word, lemma: lemma) ?? UUID().uuidString,
            word: word,
            lemma: lemma,
            surfaceForm: word,
            context: context,
            occurrenceIndex: selectionState.webSelectionOccurrenceIndex,
            scrollProgress: webScrollProgress,
            question: answer.isEmpty ? "" : AppText.localized("释义：\(word)", "Define: \(word)"),
            answer: answer,
            dictionaryTags: nil,
            dictionaryFrequency: nil,
            createdAt: createdAt,
            srs: VocabularySRSState.initial(createdAt: createdAt)
        )
        guard store.upsert(record) else {
            selectionActionToolbar.showSaveFailure()
            NSSound.beep()
            return
        }

        storedWebWordRecords.append(record)
        if !selectedWord.isEmpty {
            markCurrentWebSelectionAsStoredWord(id: id)
        }
        refreshVocabularyPanelAfterLocalSave()
        if answer.isEmpty {
            backfillDictionaryAnswerAsync(vocabularyID: record.vocabularyID, word: word)
        }
        selectionActionToolbar.showSaveResult(found: 1, inserted: 1)
        recordPersonalVocabularyQuery(word)
    }

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

    /// Establishes the PDF vocabulary language without re-extracting a spread
    /// of pages during every open. Stored contexts are already in memory and
    /// are the strongest cheap sample; a document with no saved words falls
    /// back to one visible/first page. Whole-document text extraction belongs
    /// to the reusable snapshot/index pipeline, not the first-page path.
    func updatePDFVocabularyDocumentLanguage(from records: [StoredPDFWordRecord]) {
        vocabularyDocumentLanguage = ReaderPerformance.measure(.vocabularyLanguageDetection) {
            let contexts = records.compactMap(\.context)
            if contexts.contains(where: { $0.count >= 40 }) {
                return VocabularyLanguageDetector.language(forContexts: contexts)
            }
            let page = pdfView.currentPage ?? pdfView.document?.page(at: 0)
            return VocabularyLanguageDetector.language(forSample: page?.string ?? "")
        }
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
        vocabularyState.occurrenceSearchCancellationToken?.cancel()
        let cancellationToken = PDFDocumentTextCancellationToken()
        let language = vocabularyDocumentLanguage
        vocabularyState.occurrenceSearchID = searchID
        vocabularyState.occurrenceSearchCancellationToken = cancellationToken
        ensurePDFVocabularyIndex(language: language) { [weak self] snapshot, index in
            guard let self,
                  self.vocabularyState.occurrenceSearchID == searchID,
                  self.vocabularyState.occurrenceSearchCancellationToken === cancellationToken,
                  self.currentFileMD5 == documentID else { return }
            guard let snapshot, let index else {
                self.vocabularyState.occurrenceSearchID = nil
                self.vocabularyState.occurrenceSearchCancellationToken = nil
                return
            }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let lemmasByKey = Dictionary(uniqueKeysWithValues: groups.map { ($0.key, $0.lemma) })
                guard let groupedMatches = index.matches(
                    lemmasByKey: lemmasByKey,
                    isCancelled: { cancellationToken.isCancelled }
                ) else { return }
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
                          self.vocabularyState.occurrenceSearchCancellationToken === cancellationToken,
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
        vocabularyState.occurrenceSearchCancellationToken = nil
        guard let store = pdfWordRecordStore,
              let documentID = currentFileMD5 else { return }
        let groupsByKey = Dictionary(uniqueKeysWithValues: groups.map { ($0.key, $0) })
        let knownKeys = Set(storedWordRecords.map(store.recordKey(record:)))
        let legacyGeometryPageIndexes = Set(storedWordRecords.compactMap {
            $0.textAnchor == nil ? $0.pageIndex : nil
        })
        continueBackfillingPDFVocabularyOccurrences(PDFVocabularyBackfillMaterialization(
            groupsByKey: groupsByKey,
            matches: matches,
            documentID: documentID,
            document: document,
            knownKeys: knownKeys,
            legacyGeometryPageIndexes: legacyGeometryPageIndexes
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
                guard let group = state.groupsByKey[match.groupKey] else { continue }
                let matchedText = VocabularyTextPolicy.normalizedOccurrenceText(
                    match.pageMatch.occurrence.matchedText,
                    matching: group.word
                )
                let record: StoredPDFWordRecord?
                if state.legacyGeometryPageIndexes.contains(match.pageMatch.pageIndex),
                   let page = state.document.page(at: match.pageMatch.pageIndex),
                   let selection = page.selection(for: match.pageMatch.occurrence.range) {
                    record = storedPDFVocabularyRecord(
                        selection: selection,
                        word: group.word,
                        lemma: group.lemma,
                        surfaceForm: matchedText,
                        vocabularyID: group.vocabularyID,
                        sourceText: match.pageMatch.text,
                        matchedText: matchedText,
                        sourceRange: match.pageMatch.occurrence.range
                    )
                } else {
                    record = semanticPDFVocabularyRecord(
                        pageMatch: match.pageMatch,
                        word: group.word,
                        lemma: group.lemma,
                        surfaceForm: matchedText,
                        vocabularyID: group.vocabularyID
                    )
                }
                guard let record else { continue }
                let key = store.recordKey(record: record)
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

    func saveCurrentPDFVocabularySelection(
        preferredWord: String? = nil,
        definitionAnswer: String? = nil
    ) {
        let acknowledgementStartedAt = ProcessInfo.processInfo.systemUptime
        guard currentDocumentKind == .pdf,
              let document = pdfView.document,
              let selection = pdfView.currentSelection else {
            NSSound.beep()
            return
        }
        let fallback = selectedReaderTextForToolbar()
        let selectedWord = vocabularyTextForCurrentPDFSelection(selection: selection, fallback: fallback)
        let word = VocabularyTextPolicy.normalizedVocabularyText(preferredWord ?? selectedWord)
        guard VocabularyTextPolicy.isVocabularySelection(word) else {
            NSSound.beep()
            return
        }
        let language = vocabularyDocumentLanguage
        let lemma = GermanLemmaResolver.lemma(for: word, language: language)
        if preferredWord != nil {
            let selectedKey = GermanLemmaResolver.groupingKey(word: selectedWord, language: language)
            let requestedKey = GermanLemmaResolver.groupingKey(word: word, lemma: lemma, language: language)
            guard selectedKey == requestedKey else {
                NSSound.beep()
                return
            }
        }

        if removeVocabularyWordIfSaved(word, lemma: lemma) {
            return
        }

        guard let selectedPage = selection.pages.first else {
            NSSound.beep()
            return
        }
        let selectedPageIndex = document.index(for: selectedPage)
        guard selectedPageIndex != NSNotFound else {
            NSSound.beep()
            return
        }
        let selectedPageText = selectedPage.string ?? ""
        guard var selectedRecord = storedPDFVocabularyRecord(
            selection: selection,
            word: word,
            lemma: lemma,
            surfaceForm: word,
            sourceText: selectedPageText
        ) else {
            NSSound.beep()
            return
        }
        let answer = definitionAnswer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !answer.isEmpty {
            selectedRecord.question = AppText.localized("释义：\(word)", "Define: \(word)")
            selectedRecord.answer = answer
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
        if answer.isEmpty {
            backfillDictionaryAnswerAsync(vocabularyID: selectedRecord.vocabularyID, word: word)
        }
        selectionActionToolbar.showSaveProgress(found: 1, indexedPages: 0, totalPages: document.pageCount)
        ReaderPerformance.record(
            .vocabularySaveAcknowledgement,
            milliseconds: (ProcessInfo.processInfo.systemUptime - acknowledgementStartedAt) * 1000
        )
        recordPersonalVocabularyQuery(word)

        let searchID = UUID()
        vocabularyState.occurrenceSearchCancellationToken?.cancel()
        let cancellationToken = PDFDocumentTextCancellationToken()
        vocabularyState.occurrenceSearchID = searchID
        vocabularyState.occurrenceSearchCancellationToken = cancellationToken
        beginPDFVocabularyOccurrenceDiscovery(
            word: word,
            lemma: lemma,
            language: language,
            selectedRecord: selectedRecord,
            selectedPageIndex: selectedPageIndex,
            selectedPageText: selectedPageText,
            documentID: documentID,
            totalPageCount: document.pageCount,
            searchID: searchID,
            cancellationToken: cancellationToken,
            saveStartedAt: Date()
        )
    }

    private func beginPDFVocabularyOccurrenceDiscovery(
        word: String,
        lemma: String,
        language: NLLanguage,
        selectedRecord: StoredPDFWordRecord,
        selectedPageIndex: Int,
        selectedPageText: String,
        documentID: String,
        totalPageCount: Int,
        searchID: UUID,
        cancellationToken: PDFDocumentTextCancellationToken,
        saveStartedAt: Date
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let exactFound = max(
                1,
                VocabularyOccurrenceMatcher.matches(query: word, in: selectedPageText).count
            )
            DispatchQueue.main.async {
                guard let self,
                      self.vocabularyState.occurrenceSearchID == searchID,
                      self.vocabularyState.occurrenceSearchCancellationToken === cancellationToken,
                      self.currentFileMD5 == documentID else { return }
                self.selectionActionToolbar.showExactSaveProgress(
                    found: exactFound,
                    totalPages: totalPageCount
                )
                let priorityPageIndexes = VocabularyIndexPriorityPlanner.pageIndexes(
                    pageCount: totalPageCount,
                    currentPageIndex: selectedPageIndex,
                    visiblePageIndexes: [],
                    neighborRadius: 0
                )
                self.buildPDFVocabularyPriorityIndex(
                    language: language,
                    pageIndexes: priorityPageIndexes,
                    preloadedPageTexts: [selectedPageIndex: selectedPageText]
                ) { [weak self] priorityResult in
                    self?.continuePDFVocabularyOccurrenceDiscovery(
                        priorityResult: priorityResult,
                        word: word,
                        lemma: lemma,
                        language: language,
                        selectedRecord: selectedRecord,
                        documentID: documentID,
                        searchID: searchID,
                        cancellationToken: cancellationToken,
                        saveStartedAt: saveStartedAt
                    )
                }
            }
        }
    }

    private func continuePDFVocabularyOccurrenceDiscovery(
        priorityResult: PDFVocabularyPriorityIndexResult?,
        word: String,
        lemma: String,
        language: NLLanguage,
        selectedRecord: StoredPDFWordRecord,
        documentID: String,
        searchID: UUID,
        cancellationToken: PDFDocumentTextCancellationToken,
        saveStartedAt: Date
    ) {
        guard vocabularyState.occurrenceSearchID == searchID,
              vocabularyState.occurrenceSearchCancellationToken === cancellationToken,
              currentFileMD5 == documentID else { return }
        if let priorityResult {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let found = max(
                    1,
                    priorityResult.index
                        .matches(lemma: lemma, selectedForm: word)
                        .reduce(into: 0) { $0 += $1.count }
                )
                DispatchQueue.main.async {
                    guard let self,
                          self.vocabularyState.occurrenceSearchID == searchID,
                          self.vocabularyState.occurrenceSearchCancellationToken === cancellationToken,
                          self.currentFileMD5 == documentID else { return }
                    self.selectionActionToolbar.showSaveProgress(
                        found: found,
                        indexedPages: priorityResult.pageIndexes.count,
                        totalPages: priorityResult.totalPageCount
                    )
                }
            }
        }
        ensurePDFVocabularyIndex(
            language: language,
            seed: priorityResult?.seed,
            preloadedPageTexts: priorityResult?.preloadedPageTexts ?? [:]
        ) { [weak self] snapshot, index in
            guard let self,
                  self.vocabularyState.occurrenceSearchID == searchID,
                  self.vocabularyState.occurrenceSearchCancellationToken === cancellationToken,
                  self.currentFileMD5 == documentID else { return }
            guard let snapshot, let index else {
                self.vocabularyState.occurrenceSearchID = nil
                self.vocabularyState.occurrenceSearchCancellationToken = nil
                return
            }
            let snapshotsReadyAt = Date()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let queryStartedAt = Date()
                let perPage = index.matches(lemma: lemma, selectedForm: word)
                let scanFinishedAt = Date()
                let queryMilliseconds = scanFinishedAt.timeIntervalSince(queryStartedAt) * 1000
                NSLog(
                    "LeafVocabulary save timing: snapshots=%.0fms queue=%.0fms scan=%.0fms pages=%d reused=%d",
                    snapshotsReadyAt.timeIntervalSince(saveStartedAt) * 1000,
                    queryStartedAt.timeIntervalSince(snapshotsReadyAt) * 1000,
                    queryMilliseconds,
                    snapshot.pageTexts.count,
                    index.reusedPageCount
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
                          self.vocabularyState.occurrenceSearchCancellationToken === cancellationToken,
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
        vocabularyState.occurrenceSearchCancellationToken = nil
        guard let store = pdfWordRecordStore else {
            // The selected occurrence was already committed before discovery
            // began. A cancelled document transition must not turn that durable
            // save into a visible failure.
            return
        }

        let existingRecordKeys = Set(storedWordRecords.map(store.recordKey(record:)))
        let legacyGeometryPageIndexes = Set(storedWordRecords.compactMap {
            $0.textAnchor == nil ? $0.pageIndex : nil
        })
        continueSavingPDFVocabularyOccurrences(PDFVocabularySaveMaterialization(
            word: word,
            lemma: lemma,
            selectedRecord: selectedRecord,
            matches: matches,
            documentID: documentID,
            document: document,
            existingRecordKeys: existingRecordKeys,
            legacyGeometryPageIndexes: legacyGeometryPageIndexes,
            startedAt: saveStartedAt
        ))
    }

    private func continueSavingPDFVocabularyOccurrences(_ state: PDFVocabularySaveMaterialization) {
        guard currentDocumentKind == .pdf,
              currentFileMD5 == state.documentID,
              pdfView.document === state.document,
              pdfWordRecordStore != nil else { return }

        let endIndex = min(state.nextMatchIndex + 12, state.matches.count)
        if state.nextMatchIndex < endIndex {
            for match in state.matches[state.nextMatchIndex..<endIndex] {
                let matchedText = VocabularyTextPolicy.normalizedOccurrenceText(
                    match.occurrence.matchedText,
                    matching: state.word
                )
                let record: StoredPDFWordRecord?
                if state.legacyGeometryPageIndexes.contains(match.pageIndex),
                   let page = state.document.page(at: match.pageIndex),
                   let selection = page.selection(for: match.occurrence.range) {
                    record = storedPDFVocabularyRecord(
                        selection: selection,
                        word: state.word,
                        lemma: state.lemma,
                        surfaceForm: matchedText,
                        vocabularyID: state.selectedRecord.vocabularyID,
                        sourceText: match.text,
                        matchedText: matchedText,
                        sourceRange: match.occurrence.range
                    )
                } else {
                    record = semanticPDFVocabularyRecord(
                        pageMatch: match,
                        word: state.word,
                        lemma: state.lemma,
                        surfaceForm: matchedText,
                        vocabularyID: state.selectedRecord.vocabularyID
                    )
                }
                guard let record else { continue }
                state.candidateRecords.append(record)
            }
            state.nextMatchIndex = endIndex
        }

        guard state.nextMatchIndex >= state.matches.count else {
            DispatchQueue.main.async { [weak self] in
                self?.continueSavingPDFVocabularyOccurrences(state)
            }
            return
        }

        let plan = VocabularyOccurrenceSavePlanner.plan(
            selectedRecord: state.selectedRecord,
            discoveredRecords: state.candidateRecords,
            existingRecordKeys: state.existingRecordKeys
        )
        let records = plan.recordsToInsert
        let foundCount = plan.foundCount
        let matchCount = state.matches.count
        let startedAt = state.startedAt
        let startedUptime = state.startedUptime
        let documentID = state.documentID
        let documentIdentity = ObjectIdentifier(state.document)
        let loadGeneration = documentSession.documentLoadGeneration
        // Preserve submission order with any exceptional full-snapshot retry.
        // In the common case there is no pending retry and this is a no-op.
        flushStoredWordRecordsSave()
        VocabularyOccurrencePersistence.queue.async { [weak self] in
            let writeStartedAt = ProcessInfo.processInfo.systemUptime
            let didPersist = records.isEmpty || WordRecordSQLiteStore.shared.upsertPDFRecords(
                documentID: documentID,
                records: records
            )
            let writeMilliseconds = (ProcessInfo.processInfo.systemUptime - writeStartedAt) * 1000
            DispatchQueue.main.async {
                ReaderPerformance.record(.vocabularyDatabaseWrite, milliseconds: writeMilliseconds)
                let persistenceMilliseconds = (ProcessInfo.processInfo.systemUptime - startedUptime) * 1000
                ReaderPerformance.record(.vocabularyOccurrencePersistence, milliseconds: persistenceMilliseconds)
                NSLog(
                    "LeafVocabulary save timing: persist=%.0fms total=%.0fms matches=%d",
                    persistenceMilliseconds,
                    Date().timeIntervalSince(startedAt) * 1000,
                    matchCount
                )
                guard let self,
                      self.documentSession.acceptsLoad(generation: loadGeneration),
                      self.currentDocumentKind == .pdf,
                      self.currentFileMD5 == documentID,
                      let currentDocument = self.pdfView.document,
                      ObjectIdentifier(currentDocument) == documentIdentity else { return }
                guard didPersist else {
                    // Keep the immediate selected-word acknowledgement. Discovery is
                    // additive and can be retried by a later backfill.
                    self.selectionActionToolbar.showSaveResult(found: 1, inserted: 1)
                    return
                }
                self.storedWordRecords.append(contentsOf: records)
                self.addStoredWordAnnotations(records, refineBounds: false)
                self.refreshVocabularyPanelAfterLocalSave()
                self.selectionActionToolbar.showSaveResult(
                    found: foundCount,
                    inserted: records.count + 1
                )
            }
        }
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
        let pageIndex = document.index(for: page)
        let textAnchor = sourceRange.flatMap {
            PDFTextQuoteAnchorBuilder.make(
                pageIndex: pageIndex,
                sourceRange: $0,
                sourceText: contextSource
            )
        } ?? PDFTextQuoteAnchorBuilder.make(
            pageIndex: pageIndex,
            selection: selection,
            page: page,
            sourceText: contextSource
        )
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
            pageIndex: pageIndex,
            bounds: StoredPDFWordRect(bounds),
            textAnchor: textAnchor,
            context: context,
            question: "",
            answer: "",
            dictionaryTags: nil,
            dictionaryFrequency: nil,
            createdAt: createdAt,
            srs: VocabularySRSState.initial(createdAt: createdAt)
        )
    }

    /// Persists an offscreen occurrence from its canonical page text and UTF-16
    /// range. Geometry is a viewport cache and is resolved only when this page
    /// becomes visible or the user navigates directly to the occurrence.
    private func semanticPDFVocabularyRecord(
        pageMatch: PDFVocabularyPageMatch,
        word: String,
        lemma: String,
        surfaceForm: String,
        vocabularyID: String?
    ) -> StoredPDFWordRecord? {
        guard let textAnchor = PDFTextQuoteAnchorBuilder.make(
            pageIndex: pageMatch.pageIndex,
            sourceRange: pageMatch.occurrence.range,
            sourceText: pageMatch.text
        ) else { return nil }
        let context = ReaderAIContextBuilder.selectedTextContext(
            occurrenceRange: pageMatch.occurrence.range,
            sourceText: pageMatch.text,
            radius: 24
        ).map {
            normalizedPDFVocabularyContext(ReaderAIContextBuilder.trimLeadingContextQuotes($0))
        } ?? ""
        let createdAt = Date()
        return StoredPDFWordRecord(
            id: UUID().uuidString,
            vocabularyID: vocabularyID ?? existingPDFVocabularyID(for: word, lemma: lemma) ?? UUID().uuidString,
            word: VocabularyTextPolicy.normalizedVocabularyText(word),
            lemma: lemma,
            surfaceForm: VocabularyTextPolicy.normalizedOccurrenceText(surfaceForm, matching: word),
            pageIndex: pageMatch.pageIndex,
            bounds: StoredPDFWordRect(.zero),
            textAnchor: textAnchor,
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

    func isVocabularyWordSaved(_ word: String) -> Bool {
        !vocabularyRecordIDs(for: word).isEmpty
    }

    private func vocabularyRecordIDs(for word: String, lemma: String? = nil) -> [String] {
        let language = vocabularyDocumentLanguage
        let key = GermanLemmaResolver.groupingKey(word: word, lemma: lemma, language: language)
        guard !key.isEmpty else { return [] }
        if currentDocumentKind == .pdf {
            return storedWordRecords.compactMap {
                GermanLemmaResolver.groupingKey(word: $0.word, lemma: $0.lemma, language: language) == key ? $0.id : nil
            }
        }
        return storedWebWordRecords.compactMap {
            GermanLemmaResolver.groupingKey(word: $0.word, lemma: $0.lemma, language: language) == key ? $0.id : nil
        }
    }

    private func removeVocabularyWordIfSaved(_ word: String, lemma: String? = nil) -> Bool {
        let ids = vocabularyRecordIDs(for: word, lemma: lemma)
        guard !ids.isEmpty else { return false }

        if currentDocumentKind == .pdf {
            vocabularyState.occurrenceSearchID = nil
            vocabularyState.occurrenceSearchCancellationToken?.cancel()
            vocabularyState.occurrenceSearchCancellationToken = nil
            cancelPDFVocabularyPriorityIndexBuild()
        }
        removeVocabularyRecords(ids: ids)
        refreshVocabularyPanelAfterLocalSave()
        selectionActionToolbar.showRemoveResult(removed: ids.count)
        return true
    }
}
