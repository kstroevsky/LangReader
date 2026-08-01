import Foundation
import LeafReaderCore

/// Mutable AI-panel presentation and request coordination owned by the reader
/// window. It is never a background service; network callbacks publish their
/// results back through the controller.
@MainActor
struct ReaderAIState {
    let retrievalQueryClient = AIClient()
    var suppressSearchSelectionForAIUntil = Date.distantPast
    var highlightedSelectionKeys = Set<String>()
    var aiSourceUnderlineKeys = Set<String>()
    var aiSourceLocationsByUnderlineKey: [String: AIConversationSourceLocation] = [:]
    var webAISourceLocationsByKey: [String: AIConversationSourceLocation] = [:]
    var activeAISourceUnderlines: [AIConversationSourceLocation] = []
    var conversationStore: AIConversationStore?
    var loadedConversation: SavedAIConversation?
    var pendingConversationToSave: SavedAIConversation?
    var documentPromptGeneration = 0
    var retrievalQueryTask: URLSessionDataTask?
    let conversationSaveTask = DebouncedTask(delay: 1.0)
    let preferredWidthSaveTask = DebouncedTask(delay: 0.4)
    let windowResizeLayoutTask = DebouncedTask(delay: 0.08)
    let panelResizeLayoutTask = DebouncedTask(delay: 0.05)
    var pendingPanelExpansionAction: (() -> Void)?
    var pendingSourceClickWorkItem: DispatchWorkItem?
    var isPanelCollapsed = true
    var preferredWidth: CGFloat = ReaderWindowController.loadPreferredAIWidth()
}
