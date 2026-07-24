import Foundation

extension AIChatPanel {
    struct LinkedWordBubble {
        let id: String
        let word: String
        let question: String
        let answer: String
    }

    /// Grammatical summary shown in the focused-word header: part of speech, the
    /// observed forms, and how many times the word occurs. Supplied by the owner
    /// because the panel has no access to the vocabulary records.
    struct WordFocusInfo {
        let partOfSpeech: String?
        let formsText: String?
        let occurrenceCount: Int
    }

    struct FailedAIRequest {
        let messages: [ChatMessage]
        let linkID: String?
        let linkedQuestion: String?
        let fallbackAnswer: String?
        let answerSuffix: String?
    }
}
