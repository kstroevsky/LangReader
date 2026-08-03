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
