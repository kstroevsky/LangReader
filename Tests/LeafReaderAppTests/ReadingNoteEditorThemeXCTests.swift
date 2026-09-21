import Cocoa
import XCTest
import LeafReaderCore
@testable import LeafReaderApp

@MainActor
final class ReadingNoteEditorThemeXCTests: XCTestCase {
    func testApplyingLightThemeRecolorsExistingEditorText() throws {
        let controller = ReadingNotePanelController(
            note: ReadingNote(
                id: "note",
                documentID: "document",
                documentTitle: "Document",
                documentKind: "pdf",
                quote: "Selected text",
                markdown: "Selected text",
                locator: ReadingNote.Locator(),
                createdAt: Date(timeIntervalSince1970: 0),
                updatedAt: Date(timeIntervalSince1970: 0)
            ),
            onSave: { _ in },
            onClose: { _ in },
            onShowNotes: {},
            onExportNote: { _ in },
            onDeleteNote: { _ in }
        )
        let whiteText = NSAttributedString(
            string: "Selected text",
            attributes: [.foregroundColor: NSColor.white]
        )
        controller.textView.textStorage?.setAttributedString(whiteText)

        controller.applyTheme(.original)

        let foregroundColor = try XCTUnwrap(
            controller.textView.textStorage?.attribute(
                .foregroundColor,
                at: 0,
                effectiveRange: nil
            ) as? NSColor
        )
        XCTAssertEqual(foregroundColor, ReadingNoteTheme.primaryText(.original))
        XCTAssertEqual(controller.textView.textColor, ReadingNoteTheme.primaryText(.original))
    }
}
