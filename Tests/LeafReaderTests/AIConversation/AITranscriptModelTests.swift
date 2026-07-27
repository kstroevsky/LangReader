import Foundation
import LeafReaderCore

/// The transcript's rules used to be spread across view-tree walks in
/// `AIChatPanel+BubblePersistence`, so none of them could be tested. They are
/// plain list logic now.
enum AITranscriptModelTests {
    private static func bubble(
        _ id: String,
        role: String,
        text: String = "",
        linkID: String? = nil,
        source: AIConversationSourceLocation? = nil,
        persistent: Bool = true
    ) -> TranscriptBubble {
        TranscriptBubble(
            id: id,
            role: role,
            text: text,
            renderMarkdown: true,
            collapsible: false,
            linkID: linkID,
            sourceLocation: source,
            isPersistent: persistent
        )
    }

    static func testDeletingAQuestionTakesItsAnswers() throws {
        let model = AITranscriptModel()
        model.append(bubble("q1", role: "Me"))
        model.append(bubble("a1", role: "AI"))
        model.append(bubble("a1b", role: "AI"))
        model.append(bubble("q2", role: "Me"))
        model.append(bubble("a2", role: "AI"))

        let group = model.conversationGroup(startingAt: "q1", userRole: "Me")

        try expectEqual(group.map(\.id), ["q1", "a1", "a1b"], "delete should stop before the next question")
    }

    static func testDeletingAnAnswerTakesOnlyThatAnswer() throws {
        let model = AITranscriptModel()
        model.append(bubble("q1", role: "Me"))
        model.append(bubble("a1", role: "AI"))
        model.append(bubble("q2", role: "Me"))

        let group = model.conversationGroup(startingAt: "a1", userRole: "Me")

        try expectEqual(group.map(\.id), ["a1"], "an answer should not drag the next question along")
    }

    static func testDeleteGroupSkipsLinkedWordBubbles() throws {
        let model = AITranscriptModel()
        model.append(bubble("q1", role: "Me"))
        model.append(bubble("w1", role: "Me", linkID: "word-1", persistent: false))
        model.append(bubble("a1", role: "AI"))

        let group = model.conversationGroup(startingAt: "q1", userRole: "Me")

        try expectEqual(group.map(\.id), ["q1", "a1"], "linked word bubbles are not part of the conversation")
    }

    static func testTrimDropsOldestConversationBubblesButKeepsTheStreamingOne() throws {
        let model = AITranscriptModel()
        for index in 0..<5 {
            model.append(bubble("b\(index)", role: "AI"))
        }
        model.append(bubble("linked", role: "AI", linkID: "word-1", persistent: false))

        try expectEqual(
            model.conversationBubblesToTrim(limit: 3, keeping: nil),
            ["b0", "b1"],
            "the two oldest should go, and the linked bubble should not count towards the limit"
        )
        try expectEqual(
            model.conversationBubblesToTrim(limit: 3, keeping: "b0"),
            ["b1"],
            "the bubble a request is streaming into is never trimmed"
        )
        try expectEqual(
            model.conversationBubblesToTrim(limit: 10, keeping: nil),
            [],
            "nothing to trim under the limit"
        )
    }

    static func testOnlyPersistentConversationBubblesAreSaved() throws {
        let model = AITranscriptModel()
        model.append(bubble("kept", role: "Me"))
        model.append(bubble("draft", role: "AI", persistent: false))
        model.append(bubble("linked", role: "AI", linkID: "word-1"))

        try expectEqual(
            model.savedConversationBubbles(limit: 10).map(\.id),
            ["kept"],
            "unsaved drafts and linked word bubbles stay out of the saved conversation"
        )
        try expectEqual(
            model.savedConversationBubbles(limit: 0).map(\.id),
            [],
            "a zero limit saves nothing"
        )
    }

    static func testMarkPersistentReportsWhetherItChangedAnything() throws {
        let model = AITranscriptModel()
        model.append(bubble("a", role: "AI", persistent: false))

        try expectEqual(model.markPersistent(id: "a"), true, "first mark should take effect")
        try expectEqual(model.markPersistent(id: "a"), false, "marking twice should be a no-op")
        try expectEqual(model.markPersistent(id: "missing"), false, "unknown ids should be a no-op")
        try expectEqual(model.savedConversationBubbles(limit: 10).map(\.id), ["a"], "the bubble should now be saved")
    }

    static func testUpdateContentKeepsTheBubbleKind() throws {
        let model = AITranscriptModel()
        model.append(TranscriptBubble(
            id: "a",
            role: "AI",
            text: "Generating...",
            renderMarkdown: true,
            collapsible: true,
            linkID: "word-1",
            sourceLocation: nil,
            isPersistent: true
        ))

        model.updateContent(id: "a", role: "AI", text: "final answer", renderMarkdown: false)

        let updated = model["a"]
        try expectEqual(updated?.text, "final answer", "text should update")
        try expectEqual(updated?.renderMarkdown, false, "markdown rendering should update")
        try expectEqual(updated?.collapsible, true, "collapsibility should survive a content update")
        try expectEqual(updated?.linkID, "word-1", "the link should survive a content update")
        try expectEqual(updated?.isPersistent, true, "persistence should survive a content update")
    }

    static func testRemovingLinkedBubblesReportsTheirIDs() throws {
        let model = AITranscriptModel()
        model.append(bubble("q", role: "Me"))
        model.append(bubble("w1", role: "Me", linkID: "word-1", persistent: false))
        model.append(bubble("w1a", role: "AI", linkID: "word-1", persistent: false))
        model.append(bubble("w2", role: "Me", linkID: "word-2", persistent: false))

        let removed = model.removeLinked(linkIDs: ["word-1"])

        try expectEqual(removed, ["w1", "w1a"], "both bubbles of the removed word should be reported")
        try expectEqual(model.bubbles.map(\.id), ["q", "w2"], "the other word and the conversation should remain")
        try expectEqual(model.removeLinked(linkIDs: []), [], "removing nothing should be a no-op")
    }

    static func testAppendingABubbleEndsTheFocusedWordState() throws {
        let model = AITranscriptModel()
        model.focusedWord = FocusedWord(word: "name", answer: "a definition", linkID: nil)

        model.append(bubble("q", role: "Me"))

        // Otherwise a theme change rebuilds the stale focused-word card and
        // throws away the conversation that replaced it.
        try expectEqual(model.focusedWord == nil, true, "a bubble should end the focused-word state")

        model.focusedWord = FocusedWord(word: "name", answer: "a definition", linkID: nil)
        model.removeAll()
        try expectEqual(model.focusedWord == nil, true, "clearing the transcript should clear the focus too")
    }

    static func testActiveSourcesAreDistinctAndInDisplayOrder() throws {
        let first = AIConversationSourceLocation(kind: .pdfPage, index: 3, progress: nil)
        let second = AIConversationSourceLocation(kind: .pdfPage, index: 7, progress: nil)
        let model = AITranscriptModel()
        model.append(bubble("a", role: "Me", source: first))
        model.append(bubble("b", role: "AI", source: second))
        model.append(bubble("c", role: "Me", source: first))
        model.append(bubble("d", role: "AI", source: second, persistent: false))
        model.append(bubble("e", role: "AI", linkID: "word-1", source: second))

        try expectEqual(
            model.activeSources().map(\.index),
            [3, 7],
            "each source should appear once, in the order it was first cited"
        )
        try expectEqual(model.containsSource(first), true, "a cited source should be found")
    }
}
