import Cocoa
import LeafReaderCore

extension ReaderWindowController {
    func applyCachedEmbeddingsIfPossible(completion: (() -> Void)? = nil) {
        let completionBox = completion.map(EmbeddingCompletion.init)
        guard let documentID = currentFileMD5,
              let index = pdfAgentIndex,
              let config = EmbeddingClient.configFromCurrentAISettings() else {
            completionBox?.call()
            return
        }
        index.prepareForEmbeddingCacheModel(config.cacheModelID)
        let chunks = index.indexableChunks
        guard !chunks.isEmpty else {
            completionBox?.call()
            return
        }
        let chunkIDs = chunks.map(\.id)
        let store = pdfEmbeddingStore
        embeddingStoreQueue.async { [weak self] in
            guard let self, let store else {
                DispatchQueue.main.async { completionBox?.call() }
                return
            }
            let cached = store.embeddings(documentID: documentID, model: config.cacheModelID, chunkIDs: chunkIDs)
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.currentFileMD5 == documentID,
                      EmbeddingClient.configFromCurrentAISettings()?.cacheModelID == config.cacheModelID else {
                    completionBox?.call()
                    return
                }
                self.pdfAgentIndex?.applyEmbeddings(cached, modelID: config.cacheModelID)
                if !cached.isEmpty, let progress = self.pdfAgentIndex?.embeddingCoverage {
                    self.updateEmbeddingStatusForCoverage(isComplete: progress.embedded >= progress.total)
                }
                completionBox?.call()
            }
        }
    }

    var embeddingIndexIsComplete: Bool {
        guard let progress = pdfAgentIndex?.embeddingCoverage,
              progress.total > 0 else {
            return false
        }
        return progress.embedded >= progress.total
    }

    func preparePDFEmbeddingsIfPossible(priorityPageIndex: Int? = nil, completion: (() -> Void)? = nil) {
        guard let documentID = currentFileMD5,
              pdfAgentIndex != nil,
              let config = EmbeddingClient.configFromCurrentAISettings() else {
            completion?()
            return
        }
        if applyStoredEmbeddingControlStateIfNeeded(documentID: documentID) {
            completion?()
            return
        }

        if isPreparingPDFEmbeddings {
            queuePendingEmbeddingRequest(priorityPageIndex: priorityPageIndex, completion: completion)
            return
        }

        applyCachedEmbeddingsIfPossible { [weak self] in
            guard let self else { return }
            guard self.currentFileMD5 == documentID,
                  EmbeddingClient.configFromCurrentAISettings()?.cacheModelID == config.cacheModelID,
                  self.pdfAgentIndex != nil else {
                completion?()
                return
            }
            if self.embeddingIndexIsComplete {
                self.notifyEmbeddingReady(completion, includePending: true)
                self.updateEmbeddingStatusForCoverage(isComplete: true)
                return
            }

            self.beginEmbeddingBackfill()
            let generation = self.embeddingBackfillGeneration
            self.updateEmbeddingControlButtons()
            self.continuePDFEmbeddingBackfill(
                documentID: documentID,
                config: config,
                priorityPageIndex: priorityPageIndex,
                afterFirstBatch: completion,
                notifyPendingAfterBatch: completion != nil,
                generation: generation
            )
        }
    }

    func continuePDFEmbeddingBackfill(
        documentID: String,
        config: EmbeddingModelConfig,
        priorityPageIndex: Int?,
        afterFirstBatch: (() -> Void)?,
        notifyPendingAfterBatch: Bool,
        generation: Int
    ) {
        guard generation == embeddingBackfillGeneration,
              currentFileMD5 == documentID,
              let index = pdfAgentIndex else {
            stopEmbeddingBackfill()
            notifyEmbeddingReady(afterFirstBatch, includePending: true)
            clearEmbeddingStatus()
            return
        }
        guard !isEmbeddingBackfillPaused else {
            showPausedEmbeddingStatus()
            return
        }

        let missing = index.missingEmbeddingChunks(limit: 12, preferredPageIndex: priorityPageIndex).map {
            PDFEmbeddingChunk(id: $0.id, pageIndex: $0.pageIndex, chunkIndex: $0.chunkIndex, text: $0.text)
        }
        guard !missing.isEmpty else {
            stopEmbeddingBackfill()
            notifyEmbeddingReady(afterFirstBatch, includePending: true)
            updateEmbeddingStatusForCoverage(isComplete: true)
            updateEmbeddingControlButtons()
            return
        }

        updateEmbeddingStatus(chunks: missing)
        embeddingBackfillTask?.cancel()
        embeddingBackfillTask = Task { [weak self] in
            let result: Result<[[Float]], Error>
            do {
                result = .success(try await self?.embeddingClient.embed(texts: missing.map(\.text), config: config) ?? [])
            } catch {
                result = .failure(error)
            }
            guard let self, !Task.isCancelled else { return }
            self.embeddingBackfillTask = nil
            guard generation == self.embeddingBackfillGeneration,
                  self.currentFileMD5 == documentID else {
                self.stopEmbeddingBackfill()
                self.notifyEmbeddingReady(afterFirstBatch, includePending: true)
                self.clearEmbeddingStatus()
                self.updateEmbeddingControlButtons()
                return
            }

            switch result {
            case .success(let embeddings):
                    var mapped: [String: [Float]] = [:]
                    for (chunk, embedding) in zip(missing, embeddings) {
                        mapped[chunk.id] = embedding
                    }
                    self.pdfAgentIndex?.applyEmbeddings(mapped, modelID: config.cacheModelID)
                    let nextPriorityPageIndex = self.queuedEmbeddingPriorityPageIndex
                    self.queuedEmbeddingPriorityPageIndex = nil
                    let shouldDeferPendingCallbacks = nextPriorityPageIndex != nil && !self.pendingEmbeddingReadyCallbacks.isEmpty
                    self.notifyEmbeddingReady(afterFirstBatch, includePending: notifyPendingAfterBatch && !shouldDeferPendingCallbacks)
                    self.updateEmbeddingStatusForCoverage(isComplete: false)
                    let shouldNotifyPendingAfterNextBatch = shouldDeferPendingCallbacks
                    let store = self.pdfEmbeddingStore
                    self.embeddingStoreQueue.async { [weak self] in
                        store?.save(documentID: documentID, model: config.cacheModelID, chunks: missing, embeddings: embeddings)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                            self?.continuePDFEmbeddingBackfill(
                                documentID: documentID,
                                config: config,
                                priorityPageIndex: nextPriorityPageIndex,
                                afterFirstBatch: nil,
                                notifyPendingAfterBatch: shouldNotifyPendingAfterNextBatch,
                                generation: generation
                            )
                        }
                    }
            case .failure:
                self.stopEmbeddingBackfill()
                self.embeddingBackfillNeedsRetry = true
                self.notifyEmbeddingReady(afterFirstBatch, includePending: true)
                self.showEmbeddingStatus(AppText.localized("AI 分析数据：失败，可重试", "AI analysis data: failed, retry available"))
                self.updateEmbeddingControlButtons()
            }
        }
    }

    func queuePendingEmbeddingRequest(priorityPageIndex: Int?, completion: (() -> Void)?) {
        if let priorityPageIndex {
            queuedEmbeddingPriorityPageIndex = priorityPageIndex
        }
        if let completion {
            pendingEmbeddingReadyCallbacks.append(completion)
        }
    }
}

/// A UI callback may cross the SQLite queue only as main-actor-owned state.
/// The queue never invokes the caller closure itself; it merely schedules this
/// handle back to the main actor.
@MainActor
private final class EmbeddingCompletion {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    func call() {
        action()
    }
}
