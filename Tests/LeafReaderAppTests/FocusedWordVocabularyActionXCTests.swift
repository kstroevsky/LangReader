import Cocoa
import XCTest
@testable import LeafReaderApp

@MainActor
final class FocusedWordVocabularyActionXCTests: XCTestCase {
    func testDefinitionDoesNotPersistUntilSaveIsClickedAndThenOffersRemove() throws {
        let panel = AIChatPanel(frame: NSRect(x: 0, y: 0, width: 420, height: 640))
        var isSaved = false
        var actions: [(word: String, answer: String)] = []
        panel.onWordFocusInfoRequested = { _ in
            AIChatPanel.WordFocusInfo(
                partOfSpeech: "Substantiv",
                formsText: nil,
                occurrenceCount: isSaved ? 1 : 0,
                isSaved: isSaved
            )
        }
        panel.onFocusedWordSaveToggleRequested = { word, answer in
            actions.append((word, answer))
            isSaved.toggle()
        }

        panel.showFocusedWord(word: "Südwesten", answer: "der südwestliche Teil", linkID: nil)

        XCTAssertTrue(actions.isEmpty, "showing a definition must not save the word")
        let saveButton = try XCTUnwrap(button(titled: "Save", in: panel))
        saveButton.performClick(nil)

        XCTAssertEqual(actions.map(\.word), ["Südwesten"])
        XCTAssertEqual(actions.map(\.answer), ["der südwestliche Teil"])
        XCTAssertNotNil(button(titled: "Remove", in: panel))

        let removeButton = try XCTUnwrap(button(titled: "Remove", in: panel))
        removeButton.performClick(nil)
        XCTAssertEqual(actions.count, 2)
        XCTAssertNotNil(button(titled: "Save", in: panel))
    }

    private func button(titled title: String, in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.title == title {
            return button
        }
        for subview in view.subviews {
            if let match = button(titled: title, in: subview) {
                return match
            }
        }
        return nil
    }
}
