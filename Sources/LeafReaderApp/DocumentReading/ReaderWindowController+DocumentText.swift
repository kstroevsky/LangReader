import Foundation
import NaturalLanguage
import PDFKit
import LeafReaderCore

extension ReaderWindowController {
    func ensurePDFDocumentTextSnapshot(
        completion: @escaping (PDFDocumentTextSnapshot?) -> Void
    ) {
        guard currentDocumentKind == .pdf,
              let documentID = currentFileMD5,
              let url = currentFileURL else {
            completion(nil)
            return
        }
        if let snapshot = documentTextState.snapshot,
           snapshot.documentID == documentID {
            completion(snapshot)
            return
        }

        documentTextState.pendingSnapshotCallbacks.append(completion)
        guard !documentTextState.isBuildingSnapshot else { return }

        documentTextState.isBuildingSnapshot = true
        let generation = documentTextState.generation
        let token = PDFDocumentTextCancellationToken()
        documentTextState.snapshotCancellationToken = token
        documentTextState.snapshotBuildStartedAt = ProcessInfo.processInfo.systemUptime
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let snapshot: PDFDocumentTextSnapshot? = autoreleasepool {
                guard !token.isCancelled,
                      let document = PDFDocument(url: url) else { return nil }
                var pageTexts: [String] = []
                pageTexts.reserveCapacity(document.pageCount)
                for pageIndex in 0..<document.pageCount {
                    guard !token.isCancelled else { return nil }
                    pageTexts.append(document.page(at: pageIndex)?.string ?? "")
                }
                return PDFDocumentTextSnapshot(documentID: documentID, pageTexts: pageTexts)
            }
            Task { @MainActor [weak self] in
                self?.finishPDFDocumentTextSnapshot(snapshot, generation: generation)
            }
        }
    }

    private func finishPDFDocumentTextSnapshot(
        _ snapshot: PDFDocumentTextSnapshot?,
        generation: Int
    ) {
        guard generation == documentTextState.generation else { return }
        documentTextState.snapshot = snapshot
        documentTextState.isBuildingSnapshot = false
        documentTextState.snapshotCancellationToken = nil
        if let startedAt = documentTextState.snapshotBuildStartedAt {
            ReaderPerformance.record(
                .pdfTextSnapshot,
                milliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1000
            )
        }
        documentTextState.snapshotBuildStartedAt = nil
        let callbacks = documentTextState.pendingSnapshotCallbacks
        documentTextState.pendingSnapshotCallbacks.removeAll()
        callbacks.forEach { $0(snapshot) }
    }

    func ensurePDFVocabularyIndex(
        language: NLLanguage,
        completion: @escaping (PDFDocumentTextSnapshot?, VocabularyDocumentLemmaIndex?) -> Void
    ) {
        let languageCode = language.rawValue
        if let snapshot = documentTextState.snapshot,
           let index = documentTextState.vocabularyIndex,
           documentTextState.vocabularyIndexLanguageCode == languageCode {
            completion(snapshot, index)
            return
        }

        documentTextState.pendingVocabularyIndexCallbacks.append(completion)
        guard !documentTextState.isBuildingVocabularyIndex else { return }
        documentTextState.isBuildingVocabularyIndex = true
        ensurePDFDocumentTextSnapshot { [weak self] snapshot in
            guard let self, let snapshot else {
                self?.finishPDFVocabularyIndex(nil, snapshot: nil, languageCode: languageCode, generation: self?.documentTextState.generation ?? -1)
                return
            }
            let generation = self.documentTextState.generation
            let token = PDFDocumentTextCancellationToken()
            self.documentTextState.vocabularyIndexCancellationToken = token
            self.documentTextState.vocabularyIndexBuildStartedAt = ProcessInfo.processInfo.systemUptime
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let index = VocabularyDocumentLemmaIndex(
                    texts: snapshot.pageTexts,
                    language: language,
                    maximumWorkerCount: 4,
                    isCancelled: { token.isCancelled }
                )
                Task { @MainActor [weak self] in
                    self?.finishPDFVocabularyIndex(
                        index,
                        snapshot: snapshot,
                        languageCode: languageCode,
                        generation: generation
                    )
                }
            }
        }
    }

    private func finishPDFVocabularyIndex(
        _ index: VocabularyDocumentLemmaIndex?,
        snapshot: PDFDocumentTextSnapshot?,
        languageCode: String,
        generation: Int
    ) {
        guard generation == documentTextState.generation else { return }
        documentTextState.vocabularyIndex = index
        documentTextState.vocabularyIndexLanguageCode = index == nil ? nil : languageCode
        documentTextState.isBuildingVocabularyIndex = false
        documentTextState.vocabularyIndexCancellationToken = nil
        if let startedAt = documentTextState.vocabularyIndexBuildStartedAt {
            ReaderPerformance.record(
                .vocabularyIndexBuild,
                milliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1000
            )
        }
        documentTextState.vocabularyIndexBuildStartedAt = nil
        let callbacks = documentTextState.pendingVocabularyIndexCallbacks
        documentTextState.pendingVocabularyIndexCallbacks.removeAll()
        callbacks.forEach { $0(snapshot, index) }
    }

    func invalidateDocumentTextState() {
        documentTextState.snapshotCancellationToken?.cancel()
        documentTextState.vocabularyIndexCancellationToken?.cancel()
        documentTextState.generation += 1
        documentTextState.snapshot = nil
        documentTextState.isBuildingSnapshot = false
        documentTextState.snapshotCancellationToken = nil
        documentTextState.snapshotBuildStartedAt = nil
        documentTextState.pendingSnapshotCallbacks.removeAll()
        documentTextState.vocabularyIndex = nil
        documentTextState.vocabularyIndexLanguageCode = nil
        documentTextState.isBuildingVocabularyIndex = false
        documentTextState.vocabularyIndexCancellationToken = nil
        documentTextState.vocabularyIndexBuildStartedAt = nil
        documentTextState.pendingVocabularyIndexCallbacks.removeAll()
    }
}
