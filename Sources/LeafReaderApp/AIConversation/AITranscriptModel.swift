import Foundation

/// One bubble in the AI panel's transcript.
///
/// This is the transcript's unit of *data*. Before, a bubble existed only as a
/// tree of AppKit views plus an entry in a side dictionary keyed by a UUID
/// stashed in the view's `identifier` — so the display order lived in the stack
/// view's arranged subviews and every question about the transcript had to be
/// answered by walking that tree. Now the list is the source of truth and the
/// views are rendered from it.
struct TranscriptBubble: Identifiable {
    let id: String
    var role: String
    var text: String
    var renderMarkdown: Bool
    var collapsible: Bool
    /// Set for the per-word bubbles of the vocabulary flow; `nil` for ordinary
    /// conversation. Linked bubbles are never persisted and never counted as
    /// conversation.
    var linkID: String?
    var sourceLocation: AIConversationSourceLocation?
    var regenerationRequest: RegenerationRequest?
    /// Whether this bubble belongs to the saved conversation.
    var isPersistent: Bool

    init(
        id: String = UUID().uuidString,
        role: String,
        text: String,
        renderMarkdown: Bool,
        collapsible: Bool,
        linkID: String? = nil,
        sourceLocation: AIConversationSourceLocation? = nil,
        regenerationRequest: RegenerationRequest? = nil,
        isPersistent: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.renderMarkdown = renderMarkdown
        self.collapsible = collapsible
        self.linkID = linkID
        self.sourceLocation = sourceLocation
        self.regenerationRequest = regenerationRequest
        self.isPersistent = isPersistent
    }

    /// A conversation bubble is an ordinary exchange; linked word bubbles are
    /// the vocabulary flow's own transcript and are excluded from saving,
    /// trimming, source tracking and group deletion.
    var isConversation: Bool { linkID == nil }
}

/// The single word the transcript is focused on: what "Define" and clicking a
/// saved word both produce, in place of a conversation.
struct FocusedWord {
    let word: String
    let answer: String
    let linkID: String?
}

/// What a bubble needs to be re-sent to the model when the user asks for a
/// different answer. Lives here rather than nested in the panel so the
/// transcript stays free of AppKit.
struct RegenerationRequest {
    let messages: [ChatMessage]
    let fallbackAnswer: String?
    let answerSuffix: String?
}

/// The AI panel's transcript: an ordered list of bubbles plus the queries the
/// panel used to answer by walking its own view hierarchy.
///
/// Deliberately AppKit-free — every rule here (what persists, what gets
/// trimmed, which bubbles a delete removes, which sources are active) is plain
/// logic over the list, so it is unit-testable and portable.
@Observable
final class AITranscriptModel {
    /// Display order. Appends go to the end, exactly as the stack view laid
    /// them out.
    private(set) var bubbles: [TranscriptBubble] = []

    /// Set while the transcript is showing a single word instead of a
    /// conversation. The focused-word card is drawn from scratch with the
    /// theme's colours baked in, so this is what lets it be rebuilt when the
    /// theme changes.
    var focusedWord: FocusedWord?

    // MARK: - Lookup

    subscript(id: String) -> TranscriptBubble? {
        bubbles.first { $0.id == id }
    }

    func contains(id: String) -> Bool {
        bubbles.contains { $0.id == id }
    }

    /// Bubbles that belong to the saved conversation, in display order.
    var persistentConversationBubbles: [TranscriptBubble] {
        bubbles.filter { $0.isPersistent && $0.isConversation }
    }

    /// True when any bubble already cites this source, so the panel can avoid
    /// asking the same question twice.
    func containsSource(_ source: AIConversationSourceLocation) -> Bool {
        bubbles.contains { $0.sourceLocation == source }
    }

    /// The distinct sources cited by the saved conversation, first-cited first.
    func activeSources() -> [AIConversationSourceLocation] {
        var sources: [AIConversationSourceLocation] = []
        for bubble in bubbles where bubble.isPersistent && bubble.isConversation {
            guard let source = bubble.sourceLocation, !sources.contains(source) else { continue }
            sources.append(source)
        }
        return sources
    }

    // MARK: - Mutation

    func append(_ bubble: TranscriptBubble) {
        // A bubble means the transcript is a conversation again, so it is no
        // longer showing a focused word. Without this the stale focus would
        // win the next time the card is rebuilt (on a theme change) and
        // replace the conversation with the last word looked up.
        focusedWord = nil
        bubbles.append(bubble)
    }

    /// Replaces a bubble's content, keeping everything that describes *what
    /// kind* of bubble it is. This is what a streaming answer does on every
    /// chunk.
    func updateContent(id: String, role: String, text: String, renderMarkdown: Bool) {
        guard let index = bubbles.firstIndex(where: { $0.id == id }) else { return }
        bubbles[index].role = role
        bubbles[index].text = text
        bubbles[index].renderMarkdown = renderMarkdown
    }

    /// Marks a bubble as part of the saved conversation. Returns false when it
    /// was already persistent or is unknown, so callers can skip the follow-up
    /// work.
    @discardableResult
    func markPersistent(id: String) -> Bool {
        guard let index = bubbles.firstIndex(where: { $0.id == id }), !bubbles[index].isPersistent else {
            return false
        }
        bubbles[index].isPersistent = true
        return true
    }

    func remove(id: String) {
        bubbles.removeAll { $0.id == id }
    }

    func remove(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        bubbles.removeAll { ids.contains($0.id) }
    }

    /// Removes every bubble carrying one of these link IDs, and reports which
    /// bubble IDs went away so the view side can drop the matching subviews.
    @discardableResult
    func removeLinked(linkIDs: Set<String>) -> [String] {
        guard !linkIDs.isEmpty else { return [] }
        let removed = bubbles.filter { $0.linkID.map(linkIDs.contains) == true }.map(\.id)
        bubbles.removeAll { $0.linkID.map(linkIDs.contains) == true }
        return removed
    }

    func removeAll() {
        bubbles.removeAll()
        focusedWord = nil
    }

    // MARK: - Policies

    /// The oldest conversation bubbles above the visible limit. The bubble a
    /// request is currently streaming into is never offered up.
    func conversationBubblesToTrim(limit: Int, keeping activeID: String?) -> [String] {
        let ids = persistentConversationBubbles.map(\.id)
        let excess = ids.count - limit
        guard excess > 0 else { return [] }
        return ids.prefix(excess).filter { $0 != activeID }
    }

    /// The bubbles a delete on `id` should take with it: that bubble and the
    /// conversation bubbles after it, stopping before the next user turn. So
    /// deleting a question removes its answer, and deleting an answer removes
    /// only that answer.
    func conversationGroup(startingAt id: String, userRole: String) -> [TranscriptBubble] {
        guard let startIndex = bubbles.firstIndex(where: { $0.id == id }) else { return [] }
        var group: [TranscriptBubble] = []
        for bubble in bubbles[startIndex...] where bubble.isConversation {
            if !group.isEmpty, bubble.role == userRole { break }
            group.append(bubble)
        }
        return group
    }

    /// The tail of the conversation that gets written to disk.
    func savedConversationBubbles(limit: Int) -> [TranscriptBubble] {
        Array(persistentConversationBubbles.suffix(limit))
    }
}
