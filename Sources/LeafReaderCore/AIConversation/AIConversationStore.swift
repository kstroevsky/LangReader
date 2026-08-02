import Foundation

package struct SavedAIConversation: Codable {
    package var bubbles: [SavedAIConversationBubble]

    package init(bubbles: [SavedAIConversationBubble]) {
        self.bubbles = bubbles
    }

    package static let empty = SavedAIConversation(bubbles: [])

    package static func mergedForSave(
        loaded: SavedAIConversation?,
        visible: SavedAIConversation,
        maxBubbles: Int
    ) -> SavedAIConversation {
        guard let loaded, !loaded.bubbles.isEmpty else {
            return visible
        }

        var mergedBubbles = loaded.bubbles
        var existingKeys = Set(mergedBubbles.map(conversationBubbleKey))
        for bubble in visible.bubbles where !existingKeys.contains(conversationBubbleKey(bubble)) {
            mergedBubbles.append(bubble)
            existingKeys.insert(conversationBubbleKey(bubble))
        }
        if mergedBubbles.count > maxBubbles {
            mergedBubbles = Array(mergedBubbles.suffix(maxBubbles))
        }
        return SavedAIConversation(bubbles: mergedBubbles)
    }

    package func removing(_ deletedBubbles: [SavedAIConversationBubble]) -> SavedAIConversation {
        let deletedKeys = Set(deletedBubbles.map(Self.conversationBubbleKey))
        guard !deletedKeys.isEmpty else { return self }
        return SavedAIConversation(bubbles: bubbles.filter { !deletedKeys.contains(Self.conversationBubbleKey($0)) })
    }

    package static func conversationBubbleKey(_ bubble: SavedAIConversationBubble) -> String {
        "\(bubble.role)\u{1F}\(bubble.text)"
    }
}

package struct SavedAIConversationBubble: Codable {
    package let role: String
    package let text: String
    package let collapsible: Bool
    package let renderMarkdown: Bool
    package let sourceLocation: AIConversationSourceLocation?

    package init(
        role: String,
        text: String,
        collapsible: Bool,
        renderMarkdown: Bool,
        sourceLocation: AIConversationSourceLocation?
    ) {
        self.role = role
        self.text = text
        self.collapsible = collapsible
        self.renderMarkdown = renderMarkdown
        self.sourceLocation = sourceLocation
    }
}

package struct AIConversationSourceLocation: Codable, Equatable {
    package enum Kind: String, Codable {
        case pdfPage
        case webProgress
    }

    package let kind: Kind
    package let index: Int
    package let progress: Double?
    package var selectedText: String?
    package var pdfBounds: [StoredPDFWordRect]?
    package var webContext: String?
    package var occurrenceIndex: Int?

    package init(kind: Kind, index: Int, progress: Double?, selectedText: String? = nil, pdfBounds: [StoredPDFWordRect]? = nil, webContext: String? = nil, occurrenceIndex: Int? = nil) {
        self.kind = kind
        self.index = index
        self.progress = progress
        self.selectedText = selectedText
        self.pdfBounds = pdfBounds
        self.webContext = webContext
        self.occurrenceIndex = occurrenceIndex
    }
}

package final class AIConversationStore {
    private let key: String
    private let defaults: UserDefaults

    package init(fileMD5: String, defaults: UserDefaults = .standard) {
        self.key = "aiConversation.\(fileMD5)"
        self.defaults = defaults
    }

    package func load() -> SavedAIConversation {
        guard let data = defaults.data(forKey: key) else {
            return .empty
        }
        do {
            return try JSONDecoder().decode(SavedAIConversation.self, from: data)
        } catch {
            NSLog("LeafReader AI conversation: failed to decode conversation (key=%@, error=%@)", key, error.localizedDescription)
            return .empty
        }
    }

    package func save(_ conversation: SavedAIConversation) {
        guard !conversation.bubbles.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        let data: Data
        do {
            data = try JSONEncoder().encode(conversation)
        } catch {
            NSLog("LeafReader AI conversation: failed to encode conversation (key=%@, bubbles=%d, error=%@)", key, conversation.bubbles.count, error.localizedDescription)
            return
        }
        defaults.set(data, forKey: key)
    }

    package func clear() {
        defaults.removeObject(forKey: key)
    }
}
