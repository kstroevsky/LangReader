import Foundation
import NaturalLanguage
import PDFKit
import LeafReaderCore

extension ReaderWindowController {
    func ensurePDFDocumentTextSnapshot(
        preloadedPageTexts: [Int: String] = [:],
        completion: @escaping (PDFDocumentTextSnapshot?) -> Void
    ) {
        guard currentDocumentKind == .pdf,
              let documentID = currentFileMD5,
              let url = currentFileURL,
              let expectedPageCount = pdfView.document?.pageCount else {
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
            let cache = PDFDocumentTextSnapshotCache()
            let cachedSnapshot = token.isCancelled ? nil : cache.load(
                documentID: documentID,
                expectedPageCount: expectedPageCount
            )
            let resolvedSnapshot: PDFDocumentTextSnapshot? = cachedSnapshot ?? autoreleasepool {
                guard !token.isCancelled,
                      let document = PDFDocument(url: url) else { return nil }
                var pageTexts = [String](repeating: "", count: document.pageCount)
                for pageIndex in 0..<document.pageCount {
                    guard !token.isCancelled else { return nil }
                    pageTexts[pageIndex] = preloadedPageTexts[pageIndex]
                        ?? document.page(at: pageIndex)?.string
                        ?? ""
                }
                return PDFDocumentTextSnapshot(documentID: documentID, pageTexts: pageTexts)
            }
            let snapshot = token.isCancelled ? nil : resolvedSnapshot
            let didUseCache = cachedSnapshot != nil && snapshot != nil
            if cachedSnapshot == nil, !token.isCancelled, let snapshot {
                cache.save(snapshot)
            }
            Task { @MainActor [weak self] in
                self?.finishPDFDocumentTextSnapshot(
                    snapshot,
                    generation: generation,
                    cacheHit: didUseCache
                )
            }
        }
    }

    private func finishPDFDocumentTextSnapshot(
        _ snapshot: PDFDocumentTextSnapshot?,
        generation: Int,
        cacheHit: Bool
    ) {
        guard generation == documentTextState.generation else { return }
        documentTextState.snapshot = snapshot
        documentTextState.isBuildingSnapshot = false
        documentTextState.snapshotCancellationToken = nil
        if let startedAt = documentTextState.snapshotBuildStartedAt {
            ReaderPerformance.record(
                cacheHit ? .pdfTextSnapshotCacheLoad : .pdfTextSnapshot,
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
        seed: VocabularyDocumentLemmaIndexSeed? = nil,
        preloadedPageTexts: [Int: String] = [:],
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
        ensurePDFDocumentTextSnapshot(preloadedPageTexts: preloadedPageTexts) { [weak self] snapshot in
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
                    seed: seed,
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

    /// Builds only the current/visible page slice at interactive priority. The
    /// result is explicitly partial and can later seed the complete index, so
    /// the early NLP work is reused instead of repeated.
    func buildPDFVocabularyPriorityIndex(
        language: NLLanguage,
        pageIndexes: [Int],
        preloadedPageTexts: [Int: String] = [:],
        completion: @escaping @MainActor @Sendable (PDFVocabularyPriorityIndexResult?) -> Void
    ) {
        guard currentDocumentKind == .pdf,
              let documentID = currentFileMD5,
              let url = currentFileURL,
              let document = pdfView.document else {
            completion(nil)
            return
        }
        if documentTextState.vocabularyIndex != nil,
           documentTextState.vocabularyIndexLanguageCode == language.rawValue {
            completion(nil)
            return
        }

        let totalPageCount = document.pageCount
        var seen = Set<Int>()
        let boundedPageIndexes = pageIndexes.filter {
            $0 >= 0 && $0 < totalPageCount && seen.insert($0).inserted
        }
        guard !boundedPageIndexes.isEmpty else {
            completion(nil)
            return
        }

        documentTextState.vocabularyPriorityCancellationToken?.cancel()
        let token = PDFDocumentTextCancellationToken()
        documentTextState.vocabularyPriorityCancellationToken = token
        let generation = documentTextState.generation
        let cachedSnapshot = documentTextState.snapshot
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: PDFVocabularyPriorityIndexResult? = autoreleasepool {
                guard !token.isCancelled else { return nil }
                let pageTexts: [String]
                if let cachedSnapshot,
                   cachedSnapshot.documentID == documentID,
                   cachedSnapshot.pageTexts.count == totalPageCount {
                    pageTexts = boundedPageIndexes.map { cachedSnapshot.pageTexts[$0] }
                } else if boundedPageIndexes.allSatisfy({ preloadedPageTexts[$0] != nil }) {
                    pageTexts = boundedPageIndexes.compactMap { preloadedPageTexts[$0] }
                } else {
                    guard let backgroundDocument = PDFDocument(url: url),
                          backgroundDocument.pageCount == totalPageCount else { return nil }
                    var extracted: [String] = []
                    extracted.reserveCapacity(boundedPageIndexes.count)
                    for pageIndex in boundedPageIndexes {
                        guard !token.isCancelled else { return nil }
                        extracted.append(
                            preloadedPageTexts[pageIndex]
                                ?? backgroundDocument.page(at: pageIndex)?.string
                                ?? ""
                        )
                    }
                    pageTexts = extracted
                }
                guard let index = VocabularyDocumentLemmaIndex(
                    texts: pageTexts,
                    language: language,
                    maximumWorkerCount: 2,
                    isCancelled: { token.isCancelled }
                ) else { return nil }
                return PDFVocabularyPriorityIndexResult(
                    pageIndexes: boundedPageIndexes,
                    pageTexts: pageTexts,
                    totalPageCount: totalPageCount,
                    index: index
                )
            }
            Task { @MainActor [weak self] in
                guard let self,
                      generation == self.documentTextState.generation,
                      self.currentFileMD5 == documentID,
                      self.documentTextState.vocabularyPriorityCancellationToken === token else { return }
                self.documentTextState.vocabularyPriorityCancellationToken = nil
                completion(result)
            }
        }
    }

    func cancelPDFVocabularyPriorityIndexBuild() {
        documentTextState.vocabularyPriorityCancellationToken?.cancel()
        documentTextState.vocabularyPriorityCancellationToken = nil
    }

    func invalidateDocumentTextState() {
        documentTextState.snapshotCancellationToken?.cancel()
        documentTextState.vocabularyIndexCancellationToken?.cancel()
        documentTextState.vocabularyPriorityCancellationToken?.cancel()
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
        documentTextState.vocabularyPriorityCancellationToken = nil
    }
}
