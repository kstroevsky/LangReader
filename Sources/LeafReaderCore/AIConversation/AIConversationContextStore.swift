import Foundation

package final class AIConversationContextStore {
    private let maxContextMessages: Int
    private let systemPromptProvider: () -> String

    package private(set) var transcriptEntries: [TranscriptEntry] = []
    package private(set) var messages: [ChatMessage]

    package init(maxContextMessages: Int, systemPromptProvider: @escaping () -> String) {
        self.maxContextMessages = maxContextMessages
        self.systemPromptProvider = systemPromptProvider
        messages = [ChatMessage(role: "system", content: systemPromptProvider())]
    }

    package func reset() {
        transcriptEntries.removeAll()
        messages = [ChatMessage(role: "system", content: systemPromptProvider())]
    }

    package func replaceTranscriptEntries(_ entries: [TranscriptEntry]) {
        transcriptEntries = entries
    }

    package func replaceMessages(_ newMessages: [ChatMessage]) {
        messages = newMessages
        ensureSystemMessage()
        trimMessagesIfNeeded()
    }

    package func appendTranscript(role: String, text: String, linkID: String? = nil) {
        let content = trimmed(text)
        guard !content.isEmpty else { return }
        transcriptEntries.append(TranscriptEntry(role: role, content: content, linkID: linkID))
    }

    package func appendMessage(_ message: ChatMessage) {
        messages.append(message)
        trimMessagesIfNeeded()
    }

    package func removeLinkedWordHistory(ids: Set<String>) {
        transcriptEntries.removeAll { entry in
            entry.linkID.map(ids.contains) ?? false
        }
        messages.removeAll { message in
            message.linkID.map(ids.contains) ?? false
        }
        ensureSystemMessage()
    }

    package func transcriptContext(noneText: String, maxCharacters: Int = 1000) -> String {
        guard !transcriptEntries.isEmpty else { return noneText }
        let context = transcriptEntries.map { entry in
            "\(entry.role)：\n\(entry.content)"
        }.joined(separator: "\n\n")
        return String(context.suffix(maxCharacters))
    }

    package func trimMessagesIfNeeded() {
        guard messages.count > maxContextMessages + 1 else { return }
        let systemMessage = messages.first { $0.role == "system" } ?? ChatMessage(role: "system", content: systemPromptProvider())
        let recentMessages = messages
            .filter { $0.role != "system" }
            .suffix(maxContextMessages)
        messages = [systemMessage] + recentMessages
    }

    private func ensureSystemMessage() {
        if messages.first?.role != "system" {
            messages.insert(ChatMessage(role: "system", content: systemPromptProvider()), at: 0)
        }
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
