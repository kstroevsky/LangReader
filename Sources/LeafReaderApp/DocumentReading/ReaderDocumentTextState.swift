import Foundation
import LeafReaderCore

struct PDFDocumentTextSnapshot: Sendable {
    let documentID: String
    let pageTexts: [String]

    var characterCount: Int {
        pageTexts.reduce(into: 0) { $0 += $1.utf16.count }
    }
}

struct PDFVocabularyPriorityIndexResult: Sendable {
    let pageIndexes: [Int]
    let pageTexts: [String]
    let totalPageCount: Int
    let index: VocabularyDocumentLemmaIndex

    var seed: VocabularyDocumentLemmaIndexSeed {
        VocabularyDocumentLemmaIndexSeed(pageIndexes: pageIndexes, index: index)
    }

    var preloadedPageTexts: [Int: String] {
        Dictionary(uniqueKeysWithValues: zip(pageIndexes, pageTexts))
    }
}

final class PDFDocumentTextCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var deferredUntil: TimeInterval = 0

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func deferWork(for duration: TimeInterval) {
        guard duration > 0 else { return }
        let deadline = ProcessInfo.processInfo.systemUptime + duration
        lock.lock()
        deferredUntil = max(deferredUntil, deadline)
        lock.unlock()
    }

    /// Returns `true` when cancelled. Background work calls this at bounded
    /// checkpoints so reader input wins without spinning or blocking the main
    /// thread. Cancellation latency remains bounded by the 50ms sleep slice.
    func waitUntilRunnableOrCancelled() -> Bool {
        while true {
            lock.lock()
            let shouldCancel = cancelled
            let delay = deferredUntil - ProcessInfo.processInfo.systemUptime
            lock.unlock()
            if shouldCancel { return true }
            if delay <= 0 { return false }
            Thread.sleep(forTimeInterval: min(delay, 0.05))
        }
    }
}

struct ReaderDocumentTextState {
    var snapshot: PDFDocumentTextSnapshot?
    var isBuildingSnapshot = false
    var generation = 0
    var snapshotCancellationToken: PDFDocumentTextCancellationToken?
    var snapshotBuildStartedAt: TimeInterval?
    var pendingSnapshotCallbacks: [(PDFDocumentTextSnapshot?) -> Void] = []

    var vocabularyIndex: VocabularyDocumentLemmaIndex?
    var vocabularyIndexLanguageCode: String?
    var isBuildingVocabularyIndex = false
    var vocabularyIndexCancellationToken: PDFDocumentTextCancellationToken?
    var vocabularyIndexBuildStartedAt: TimeInterval?
    var pendingVocabularyIndexCallbacks: [(PDFDocumentTextSnapshot?, VocabularyDocumentLemmaIndex?) -> Void] = []

    var vocabularyPriorityCancellationToken: PDFDocumentTextCancellationToken?
}
