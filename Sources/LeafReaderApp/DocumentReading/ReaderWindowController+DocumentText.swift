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
              let expectedPageCount = activePagedReaderBackend?.pageCount else {
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
            let contentFingerprint = token.isCancelled
                ? nil
                : DocumentContentFingerprint.sha256(for: url)
            let cachedSnapshot = contentFingerprint.flatMap {
                token.isCancelled ? nil : cache.load(
                    documentID: documentID,
                    contentFingerprint: $0,
                    expectedPageCount: expectedPageCount
                )
            }
            let resolvedSnapshot: PDFDocumentTextSnapshot? = cachedSnapshot ?? autoreleasepool {
                guard !token.isCancelled,
                      let document = PDFDocument(url: url) else { return nil }
                var pageTexts = [String](repeating: "", count: document.pageCount)
                for pageIndex in 0..<document.pageCount {
                    guard !token.waitUntilRunnableOrCancelled() else { return nil }
                    pageTexts[pageIndex] = preloadedPageTexts[pageIndex]
                        ?? document.page(at: pageIndex)?.string
                        ?? ""
                }
                return PDFDocumentTextSnapshot(documentID: documentID, pageTexts: pageTexts)
            }
            let snapshot = token.isCancelled ? nil : resolvedSnapshot
            let didUseCache = cachedSnapshot != nil && snapshot != nil
            if cachedSnapshot == nil,
               !token.isCancelled,
               let snapshot,
               let contentFingerprint {
                cache.save(snapshot, contentFingerprint: contentFingerprint)
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
        language: VocabularyLanguageID,
        seed: VocabularyDocumentLemmaIndexSeed? = nil,
        preloadedPageTexts: [Int: String] = [:],
        completion: @escaping (PDFDocumentTextSnapshot?, VocabularyDocumentLemmaIndex?) -> Void
    ) {
        let runtime = vocabularyLanguageCatalog.resolve(language: language)
        let semanticIdentity = runtime?.linguisticCacheIdentity
            ?? VocabularyLinguisticCacheIdentity(language: language)
        let analyzerFactory = runtime?.linguisticAnalyzerFactory ?? .exactForm
        if let snapshot = documentTextState.snapshot,
           let index = documentTextState.vocabularyIndex,
           documentTextState.vocabularyIndexSemanticIdentity == semanticIdentity {
            completion(snapshot, index)
            return
        }

        let staleCallbacks = documentTextState.cancelVocabularyIndexBuildIfSemanticsChanged(
            to: semanticIdentity
        )
        staleCallbacks.forEach { $0(nil, nil) }

        documentTextState.pendingVocabularyIndexCallbacks.append(completion)
        guard !documentTextState.isBuildingVocabularyIndex else { return }
        documentTextState.isBuildingVocabularyIndex = true
        documentTextState.vocabularyIndexBuildSemanticIdentity = semanticIdentity
        let token = PDFDocumentTextCancellationToken()
        documentTextState.vocabularyIndexCancellationToken = token
        ensurePDFDocumentTextSnapshot(preloadedPageTexts: preloadedPageTexts) { [weak self] snapshot in
            guard let self,
                  self.documentTextState.vocabularyIndexCancellationToken === token,
                  self.documentTextState.vocabularyIndexBuildSemanticIdentity == semanticIdentity else {
                return
            }
            guard let snapshot else {
                self.finishPDFVocabularyIndex(
                    nil,
                    snapshot: nil,
                    semanticIdentity: semanticIdentity,
                    generation: self.documentTextState.generation,
                    token: token
                )
                return
            }
            let generation = self.documentTextState.generation
            self.documentTextState.vocabularyIndexBuildStartedAt = ProcessInfo.processInfo.systemUptime
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let index = VocabularyDocumentLemmaIndex(
                    texts: snapshot.pageTexts,
                    language: language,
                    maximumWorkerCount: 4,
                    seed: seed,
                    semanticIdentity: semanticIdentity,
                    analyzerFactory: analyzerFactory,
                    isCancelled: { token.waitUntilRunnableOrCancelled() }
                )
                Task { @MainActor [weak self] in
                    self?.finishPDFVocabularyIndex(
                        index,
                        snapshot: snapshot,
                        semanticIdentity: semanticIdentity,
                        generation: generation,
                        token: token
                    )
                }
            }
        }
    }

    private func finishPDFVocabularyIndex(
        _ index: VocabularyDocumentLemmaIndex?,
        snapshot: PDFDocumentTextSnapshot?,
        semanticIdentity: VocabularyLinguisticCacheIdentity,
        generation: Int,
        token: PDFDocumentTextCancellationToken
    ) {
        guard generation == documentTextState.generation,
              documentTextState.vocabularyIndexCancellationToken === token,
              documentTextState.vocabularyIndexBuildSemanticIdentity == semanticIdentity else {
            return
        }
        documentTextState.vocabularyIndex = index
        documentTextState.vocabularyIndexSemanticIdentity = index == nil ? nil : semanticIdentity
        documentTextState.isBuildingVocabularyIndex = false
        documentTextState.vocabularyIndexBuildSemanticIdentity = nil
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
        language: VocabularyLanguageID,
        pageIndexes: [Int],
        preloadedPageTexts: [Int: String] = [:],
        completion: @escaping @MainActor @Sendable (PDFVocabularyPriorityIndexResult?) -> Void
    ) {
        let runtime = vocabularyLanguageCatalog.resolve(language: language)
        let semanticIdentity = runtime?.linguisticCacheIdentity
            ?? VocabularyLinguisticCacheIdentity(language: language)
        let analyzerFactory = runtime?.linguisticAnalyzerFactory ?? .exactForm
        guard currentDocumentKind == .pdf,
              let documentID = currentFileMD5,
              let url = currentFileURL,
              let totalPageCount = activePagedReaderBackend?.pageCount else {
            completion(nil)
            return
        }
        if documentTextState.vocabularyIndex != nil,
           documentTextState.vocabularyIndexSemanticIdentity == semanticIdentity {
            completion(nil)
            return
        }

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
                    semanticIdentity: semanticIdentity,
                    analyzerFactory: analyzerFactory,
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
        vocabularyState.occurrenceSearchCancellationToken?.cancel()
        vocabularyState.occurrenceSearchCancellationToken = nil
        vocabularyState.occurrenceSearchID = nil
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
        documentTextState.vocabularyIndexSemanticIdentity = nil
        documentTextState.isBuildingVocabularyIndex = false
        documentTextState.vocabularyIndexBuildSemanticIdentity = nil
        documentTextState.vocabularyIndexCancellationToken = nil
        documentTextState.vocabularyIndexBuildStartedAt = nil
        documentTextState.pendingVocabularyIndexCallbacks.removeAll()
        documentTextState.vocabularyPriorityCancellationToken = nil
    }
}
