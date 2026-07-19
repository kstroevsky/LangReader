import Cocoa
import PDFKit

private struct PDFVocabularyPageSnapshot {
    let pageIndex: Int
    let text: String
}

private struct PDFVocabularyPageMatch {
    let pageIndex: Int
    let text: String
    let occurrence: VocabularyTextOccurrence
}

extension ReaderWindowController {
    func saveCurrentPDFVocabularySelection() {
        guard currentDocumentKind == .pdf,
              let document = pdfView.document,
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

        if removeCurrentPDFVocabularySelectionIfSaved(word) {
            return
        }

        guard let selectedRecord = storedPDFVocabularyRecord(selection: selection, word: word) else {
            NSSound.beep()
            return
        }

        let searchID = UUID()
        vocabularyState.occurrenceSearchID = searchID
        selectionActionToolbar.showSaveInProgress()
        recordPersonalVocabularyQuery(word)

        collectPDFVocabularyPageSnapshots(document: document, searchID: searchID) { [weak self, weak document] snapshots in
            DispatchQueue.global(qos: .userInitiated).async { [weak self, weak document] in
                let matches = snapshots.flatMap { snapshot in
                    VocabularyOccurrenceMatcher.matches(query: word, in: snapshot.text).map {
                        PDFVocabularyPageMatch(
                            pageIndex: snapshot.pageIndex,
                            text: snapshot.text,
                            occurrence: $0
                        )
                    }
                }
                DispatchQueue.main.async {
                    guard let self,
                          let document,
                          self.vocabularyState.occurrenceSearchID == searchID,
                          self.pdfView.document === document else {
                        return
                    }
                    self.finishSavingAllPDFVocabularyOccurrences(
                        word: word,
                        selectedRecord: selectedRecord,
                        matches: matches,
                        document: document
                    )
                }
            }
        }
    }

    private func collectPDFVocabularyPageSnapshots(
        document: PDFDocument,
        searchID: UUID,
        pageIndex: Int = 0,
        snapshots: [PDFVocabularyPageSnapshot] = [],
        completion: @escaping ([PDFVocabularyPageSnapshot]) -> Void
    ) {
        guard vocabularyState.occurrenceSearchID == searchID,
              pdfView.document === document else {
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
        DispatchQueue.main.async { [weak self, weak document] in
            guard let self, let document else { return }
            self.collectPDFVocabularyPageSnapshots(
                document: document,
                searchID: searchID,
                pageIndex: nextPageIndex,
                snapshots: collected,
                completion: completion
            )
        }
    }

    private func finishSavingAllPDFVocabularyOccurrences(
        word: String,
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

        appendIfNeeded(selectedRecord)
        for match in matches {
            guard let page = document.page(at: match.pageIndex),
                  let selection = page.selection(for: match.occurrence.range),
                  let record = storedPDFVocabularyRecord(
                    selection: selection,
                    word: word,
                    vocabularyID: selectedRecord.vocabularyID,
                    sourceText: match.text,
                    matchedText: match.occurrence.matchedText
                  ) else {
                continue
            }
            appendIfNeeded(record)
        }

        guard store.upsert(newRecords) else {
            selectionActionToolbar.showSaveFailure()
            NSSound.beep()
            return
        }
        storedWordRecords.append(contentsOf: newRecords)
        newRecords.forEach(addStoredWordAnnotation)
        refreshVocabularyPanelAfterLocalSave()
        backfillDictionaryAnswerAsync(vocabularyID: selectedRecord.vocabularyID, word: word)
        selectionActionToolbar.showSaveResult(found: foundKeys.count, inserted: newRecords.count)
    }

    private func storedPDFVocabularyRecord(
        selection: PDFSelection,
        word: String,
        vocabularyID: String? = nil,
        sourceText: String? = nil,
        matchedText: String? = nil
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
        let context = ReaderAIContextBuilder.selectedTextContext(
            selectedText: selectedText,
            sourceText: contextSource,
            radius: 24
        ).map {
            normalizedPDFVocabularyContext(ReaderAIContextBuilder.trimLeadingContextQuotes($0))
        } ?? ""
        let createdAt = Date()
        return StoredPDFWordRecord(
            id: UUID().uuidString,
            vocabularyID: vocabularyID ?? existingPDFVocabularyID(for: word) ?? UUID().uuidString,
            word: VocabularyTextPolicy.normalizedVocabularyText(word),
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

    func existingPDFVocabularyID(for word: String) -> String? {
        let key = VocabularyTextPolicy.canonicalVocabularyKey(word)
        return storedWordRecords.first {
            VocabularyTextPolicy.canonicalVocabularyKey($0.word) == key
        }?.vocabularyID
    }

    func isPDFVocabularySelectionSaved(_ word: String) -> Bool {
        let key = VocabularyTextPolicy.canonicalVocabularyKey(word)
        return !key.isEmpty && storedWordRecords.contains {
            VocabularyTextPolicy.canonicalVocabularyKey($0.word) == key
        }
    }

    private func removeCurrentPDFVocabularySelectionIfSaved(_ word: String) -> Bool {
        let key = VocabularyTextPolicy.canonicalVocabularyKey(word)
        let ids = storedWordRecords.compactMap { record in
            VocabularyTextPolicy.canonicalVocabularyKey(record.word) == key ? record.id : nil
        }
        guard !ids.isEmpty else { return false }

        removeVocabularyRecords(ids: ids)
        refreshVocabularyPanelAfterLocalSave()
        selectionActionToolbar.showRemoveResult(removed: ids.count)
        return true
    }
}
