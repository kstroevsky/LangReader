import Cocoa
import LeafReaderCore

extension AIChatPanel {
    func persistBubbleIfNeeded(_ body: NSTextField?) {
        guard let bodyID = body?.identifier?.rawValue,
              let bubble = transcript[bodyID],
              !bubble.isPersistent,
              shouldPersistBubble(role: bubble.role, text: bubble.text, linkID: bubble.linkID),
              transcript.markPersistent(id: bodyID) else {
            return
        }
        trimVisibleNormalConversationBubblesIfNeeded()
        notifyConversationChangedIfNeeded()
    }

    func trimVisibleNormalConversationBubblesIfNeeded() {
        let stale = transcript.conversationBubblesToTrim(
            limit: Self.maxVisibleNormalConversationBubbles,
            keeping: requestState.assistantBody?.identifier?.rawValue
        )
        for bodyID in stale {
            removeConversationBubble(bodyID: bodyID)
        }
    }

    func removeConversationBubble(bodyID: String) {
        guard transcript[bodyID]?.isConversation == true else { return }
        removeBubbleView(bodyID: bodyID)
        transcript.remove(id: bodyID)
        notifyConversationChangedIfNeeded()
    }

    @objc func deleteBubble(_ sender: NSButton) {
        guard let bodyID = sender.identifier?.rawValue,
              let bubble = transcript[bodyID] else {
            return
        }
        if let linkID = bubble.linkID {
            if let onLinkedBubbleDeleted {
                onLinkedBubbleDeleted(linkID)
            } else {
                removeLinkedWordBubbles(ids: [linkID])
            }
            return
        }
        removeConversationBubbleGroup(startingAt: bodyID)
    }

    func removeBubbleView(bodyID: String) {
        for view in transcriptStack.arrangedSubviews {
            guard let box = view as? ChatBubbleView,
                  box.subviews.contains(where: { ($0 as? NSTextField)?.identifier?.rawValue == bodyID }) else {
                continue
            }
            transcriptStack.removeArrangedSubview(box)
            box.removeFromSuperview()
            break
        }
    }

    func removeConversationBubbleGroup(startingAt bodyID: String) {
        // Which bubbles go is a question about the transcript, not the view
        // tree: the bubble plus the answers that follow it, up to the next
        // user turn.
        let group = transcript.conversationGroup(startingAt: bodyID, userRole: AppText.userRole)
        guard !group.isEmpty else { return }

        for bubble in group {
            removeBubbleView(bodyID: bubble.id)
        }
        transcript.remove(ids: Set(group.map(\.id)))
        onConversationBubblesDeleted?(group.map(savedBubble(from:)))
        notifyConversationChangedIfNeeded()
        transcriptStack.needsLayout = true
        scheduleTranscriptLayout()
    }

    func bodyIDForBubbleBox(_ box: ChatBubbleView) -> String? {
        box.subviews
            .compactMap { $0 as? NSTextField }
            .compactMap { $0.identifier?.rawValue }
            .first { transcript.contains(id: $0) }
    }

    func textField(forBodyID bodyID: String) -> NSTextField? {
        for view in transcriptStack.arrangedSubviews {
            guard let box = view as? ChatBubbleView else { continue }
            if let textField = box.subviews.compactMap({ $0 as? NSTextField }).first(where: { $0.identifier?.rawValue == bodyID }) {
                return textField
            }
        }
        return nil
    }

    func savedConversation() -> SavedAIConversation {
        SavedAIConversation(
            bubbles: transcript
                .savedConversationBubbles(limit: Self.maxSavedConversationBubbles)
                .map(savedBubble(from:))
        )
    }

    func savedBubble(from bubble: TranscriptBubble) -> SavedAIConversationBubble {
        SavedAIConversationBubble(
            role: bubble.role,
            text: bubble.text,
            collapsible: bubble.collapsible,
            renderMarkdown: bubble.renderMarkdown,
            sourceLocation: bubble.sourceLocation
        )
    }

    func defaultSourceLocation(role: String, text: String, linkID: String?) -> AIConversationSourceLocation? {
        guard shouldPersistBubble(role: role, text: text, linkID: linkID) else { return nil }
        return onCurrentSourceLocation?()
    }

    func shouldPersistBubble(role: String, text: String, linkID: String?) -> Bool {
        guard !isLoadingLinkedWordBubbles else { return false }
        if linkID != nil {
            return false
        }
        return role == AppText.userRole || role == AppText.aiRole || role == AppText.errorRole
    }

    func notifyConversationChangedIfNeeded() {
        guard !isRestoringSavedConversation else { return }
        onConversationChanged?(savedConversation())
        let sources = activeConversationSources()
        if sources != lastNotifiedConversationSources {
            lastNotifiedConversationSources = sources
            onConversationSourcesChanged?(sources)
        }
    }

    func activeConversationSources() -> [AIConversationSourceLocation] {
        transcript.activeSources()
    }
}
