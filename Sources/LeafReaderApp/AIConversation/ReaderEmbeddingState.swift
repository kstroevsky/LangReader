import Foundation
import LeafReaderCore

struct ReaderEmbeddingState {
    var pdfAgentIndex: PDFDocumentAgentIndex?
    var isBuildingDocumentAgentIndex = false
    var documentAgentIndexGeneration = 0
    var pendingDocumentAgentIndexCallbacks: [() -> Void] = []
    var pdfEmbeddingStore = PDFEmbeddingStore()
    let embeddingStoreQueue = DispatchQueue(label: "com.linlu.leafreader.embedding-store", qos: .utility)
    let embeddingClient = EmbeddingClient()
    var embeddingBackfillTask: Task<Void, Never>?
    var embeddingQueryTask: Task<Void, Never>?
    var isPreparingPDFEmbeddings = false
    var isEmbeddingBackfillPaused = false
    var embeddingBackfillNeedsRetry = false
    var queuedEmbeddingPriorityPageIndex: Int?
    var pendingEmbeddingReadyCallbacks: [() -> Void] = []
    var embeddingBackfillGeneration = 0
    var scheduledEmbeddingCacheRestoreWorkItem: DispatchWorkItem?
    var scheduledEmbeddingWarmupWorkItem: DispatchWorkItem?
    var lastReaderInteractionAt = Date()
}
