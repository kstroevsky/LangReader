import Cocoa
import XCTest
@testable import LeafReaderApp

@MainActor
final class SelectionActionToolbarXCTests: XCTestCase {
    func testNoteRemainsVisibleWithoutAIModelAvailability() throws {
        let toolbar = SelectionActionToolbar()
        let noteButton = try XCTUnwrap(
            toolbar.descendants
                .compactMap { $0 as? SelectionActionButton }
                .first { $0.symbolName == "note.text" }
        )

        let modesWithoutAvailableModel: [SelectionToolbarDisplayMode] = [
            .offlineWord,
            .offlineText,
            .needsModelKeyWord,
            .needsModelKeyText
        ]

        for mode in modesWithoutAvailableModel {
            toolbar.setDisplayMode(mode)
            XCTAssertFalse(noteButton.isHidden, "Note should remain available in \(mode)")
        }
    }
}

private extension NSView {
    var descendants: [NSView] {
        subviews + subviews.flatMap(\.descendants)
    }
}
