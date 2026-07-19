import Cocoa

extension ReaderWindowController {
    @objc func showVocabularyLibrary() {
        vocabularyLibraryWindowController.show(records: makeVocabularyLibraryRecords())
    }

    func makeVocabularyLibraryRecords() -> [VocabularyLibraryRecord] {
        let currentPath = currentFileURL?.standardizedFileURL.path
        let sources = RecentDocumentsStore.load().compactMap { item -> VocabularyLibrarySource? in
            let url = URL(fileURLWithPath: item.path).standardizedFileURL
            guard let kind = ReaderDocumentKind.kind(for: url),
                  let documentID = fileMD5(for: url) else {
                return nil
            }
            let records: [VocabularyExportRecord]
            if url.path == currentPath {
                records = makeCurrentVocabularyExportRecords()
            } else {
                records = VocabularyRecordProvider.records(
                    documentKind: kind,
                    pdfRecords: PDFWordRecordStore(fileMD5: documentID).load(),
                    webRecords: WebWordRecordStore(fileMD5: documentID).load(),
                    pdfContext: { $0.context ?? "" }
                )
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
