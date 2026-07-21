import Cocoa

extension ReaderWindowController {
    @objc func showVocabularyLibrary() {
        // Open the window immediately; the library scan (SQLite loads + form
        // labeling across every recent document) can take a second or two and
        // must not block the click. Records arrive via `apply(records:)`.
        vocabularyLibraryWindowController.present()
        reloadVocabularyLibraryInBackground()
    }

    /// Opens the Words window pre-selected on `word` — the destination of the
    /// Assistant's Occurrences button. The word is matched against lemma and
    /// observed forms inside the window, so the surface spelling is enough.
    func openWordsWindow(focusingWord word: String) {
        let key = VocabularyTextPolicy.canonicalVocabularyKey(word)
        vocabularyLibraryWindowController.present(focusWordKey: key)
        reloadVocabularyLibraryInBackground()
    }

    /// Rebuilds the library records off the main thread and hands them to the
    /// window when done.
    ///
    /// The only main-thread work is a cheap snapshot of the in-memory record
    /// arrays (value types, copy-on-write). Everything expensive — form labeling
    /// via the flexion cache and per-document SQLite reads — runs on the
    /// background queue; the store serializes access internally, so this is safe.
    ///
    /// The current document is built from its stored context here rather than
    /// re-extracting it from live PDFKit (which is main-thread-only and was the
    /// ~1.3s that blocked the window from painting). That matches how every
    /// other document in the list is already handled, so the current document is
    /// no longer a special, slow case.
    func reloadVocabularyLibraryInBackground() {
        let currentPath = currentFileURL?.standardizedFileURL.path
        let currentDocumentID = currentFileURL.flatMap { fileMD5(for: $0) }
        let currentKind = currentDocumentKind
        let currentPDFRecords = storedWordRecords
        let currentWebRecords = storedWebWordRecords
        let language = vocabularyDocumentLanguage
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let currentRecords: [VocabularyExportRecord]
            if let currentDocumentID {
                let fingerprint = VocabularyLibraryBuildCache.fingerprint(
                    pdf: currentPDFRecords,
                    web: currentWebRecords,
                    labelGeneration: GermanLabelCacheGeneration.current
                )
                currentRecords = self.vocabularyLibraryBuildCache.records(
                    documentID: currentDocumentID,
                    fingerprint: fingerprint
                ) {
                    VocabularyRecordProvider.records(
                        documentKind: currentKind,
                        pdfRecords: currentPDFRecords,
                        webRecords: currentWebRecords,
                        pdfContext: { $0.context ?? "" },
                        formLabel: VocabularyFormLabeling.persistentCachedFormLabelResolver(language: language)
                    )
                }
            } else {
                currentRecords = VocabularyRecordProvider.records(
                    documentKind: currentKind,
                    pdfRecords: currentPDFRecords,
                    webRecords: currentWebRecords,
                    pdfContext: { $0.context ?? "" },
                    formLabel: VocabularyFormLabeling.persistentCachedFormLabelResolver(language: language)
                )
            }
            let records = self.makeVocabularyLibraryRecords(
                currentPath: currentPath,
                currentRecords: currentRecords
            )
            DispatchQueue.main.async {
                self.vocabularyLibraryWindowController.apply(records: records)
            }
        }
    }

    func makeVocabularyLibraryRecords() -> [VocabularyLibraryRecord] {
        makeVocabularyLibraryRecords(
            currentPath: currentFileURL?.standardizedFileURL.path,
            currentRecords: makeCurrentVocabularyExportRecords()
        )
    }

    /// Background-safe: uses the pre-snapshotted current-document records rather
    /// than reaching back into PDFKit, so it can run off the main thread.
    func makeVocabularyLibraryRecords(
        currentPath: String?,
        currentRecords: [VocabularyExportRecord]
    ) -> [VocabularyLibraryRecord] {
        let sources = RecentDocumentsStore.load().compactMap { item -> VocabularyLibrarySource? in
            let url = URL(fileURLWithPath: item.path).standardizedFileURL
            guard let kind = ReaderDocumentKind.kind(for: url),
                  let documentID = fileMD5(for: url) else {
                return nil
            }
            let records: [VocabularyExportRecord]
            if let currentPath, url.path == currentPath {
                records = currentRecords
            } else {
                let pdfRecords = PDFWordRecordStore(fileMD5: documentID).load()
                let webRecords = WebWordRecordStore(fileMD5: documentID).load()
                let fingerprint = VocabularyLibraryBuildCache.fingerprint(
                    pdf: pdfRecords,
                    web: webRecords,
                    labelGeneration: GermanLabelCacheGeneration.current
                )
                // This document is not the open one, so its language has to come
                // from the contexts saved with its own words.
                let otherLanguage = VocabularyLanguageDetector.language(
                    forContexts: pdfRecords.compactMap(\.context) + webRecords.map(\.context)
                )
                records = vocabularyLibraryBuildCache.records(
                    documentID: documentID,
                    fingerprint: fingerprint
                ) {
                    VocabularyRecordProvider.records(
                        documentKind: kind,
                        pdfRecords: pdfRecords,
                        webRecords: webRecords,
                        pdfContext: { $0.context ?? "" },
                        formLabel: VocabularyFormLabeling.persistentCachedFormLabelResolver(language: otherLanguage)
                    )
                }
            }
            guard !records.isEmpty else { return nil }
            return VocabularyLibrarySource(
                documentURL: url,
                documentTitle: item.title,
                documentKind: kind,
                records: records
            )
        }
        return VocabularyLibraryRecordProvider.records(sources: sources)
    }

    /// Deletes a saved word and every one of its occurrences, across all the
    /// documents it appears in.
    ///
    /// Occurrences are grouped by document because each document owns its own
    /// store. The currently open document is routed through
    /// `removeVocabularyRecords`, which also updates the in-memory record array,
    /// PDF annotations, and highlights — deleting its rows straight from SQLite
    /// would leave that state stale and a later save could resurrect them. Other
    /// documents, which have no live in-memory state, are deleted directly.
    func deleteVocabularyLibraryRecord(_ record: VocabularyLibraryRecord) {
        let currentPath = currentFileURL?.standardizedFileURL.path

        struct DocumentGroup {
            let url: URL
            let kind: ReaderDocumentKind
            var ids: [String]
        }
        var groups: [String: DocumentGroup] = [:]
        for occurrence in record.occurrences {
            let path = occurrence.documentURL.standardizedFileURL.path
            groups[
                path,
                default: DocumentGroup(url: occurrence.documentURL, kind: occurrence.documentKind, ids: [])
            ].ids.append(occurrence.recordID)
        }

        for (path, group) in groups {
            let ids = group.ids.filter { !$0.isEmpty }
            guard !ids.isEmpty else { continue }
            if path == currentPath {
                removeVocabularyRecords(ids: ids)
            } else if let documentID = fileMD5(for: group.url) {
                if group.kind == .pdf {
                    _ = PDFWordRecordStore(fileMD5: documentID).delete(ids: ids)
                } else {
                    _ = WebWordRecordStore(fileMD5: documentID).delete(ids: ids)
                }
            }
        }
    }

    /// Grammatical summary of a word for the Assistant's focused-word header.
    ///
    /// Built from stored context (no live PDFKit extraction) so it stays cheap
    /// enough to run on the main thread when a word is defined or clicked; the
    /// persistent label cache makes the labeling effectively free once warm.
    func wordFocusInfo(for word: String) -> AIChatPanel.WordFocusInfo? {
        let key = VocabularyTextPolicy.canonicalVocabularyKey(word)
        guard !key.isEmpty else { return nil }
        let records = VocabularyRecordProvider.records(
            documentKind: currentDocumentKind,
            pdfRecords: storedWordRecords,
            webRecords: storedWebWordRecords,
            pdfContext: { $0.context ?? "" },
            formLabel: VocabularyFormLabeling.persistentCachedFormLabelResolver(language: vocabularyDocumentLanguage)
        )
        guard let record = records.first(where: { candidate in
            VocabularyTextPolicy.canonicalVocabularyKey(candidate.lemma ?? candidate.word) == key
                || VocabularyTextPolicy.canonicalVocabularyKey(candidate.word) == key
                || candidate.forms.contains { VocabularyTextPolicy.canonicalVocabularyKey($0.surface) == key }
        }) else {
            return nil
        }
        let hasInformativeForm = record.forms.contains { $0.label?.isInformative == true }
        let formsText = (record.forms.count > 1 || hasInformativeForm)
            ? record.forms.map(\.displayText).joined(separator: " · ")
            : nil
        return AIChatPanel.WordFocusInfo(
            partOfSpeech: record.dictionaryTags,
            formsText: formsText,
            occurrenceCount: record.occurrences.count
        )
    }

    func openVocabularyLibraryOccurrence(_ occurrence: VocabularyLibraryOccurrence) {
        let targetURL = occurrence.documentURL.standardizedFileURL
        if currentFileURL?.standardizedFileURL.path == targetURL.path {
            bringReaderToFrontAndJump(to: occurrence)
            return
        }
        vocabularyState.pendingLibraryOccurrence = occurrence
        loadDocument(targetURL)
    }

    func completePendingVocabularyLibraryNavigationIfNeeded() {
        guard let occurrence = vocabularyState.pendingLibraryOccurrence,
              currentFileURL?.standardizedFileURL.path == occurrence.documentURL.standardizedFileURL.path else {
            return
        }
        vocabularyState.pendingLibraryOccurrence = nil
        bringReaderToFrontAndJump(to: occurrence)
    }

    private func bringReaderToFrontAndJump(to occurrence: VocabularyLibraryOccurrence) {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        jumpToStoredLinkedWord(linkID: occurrence.recordID)
    }
}
