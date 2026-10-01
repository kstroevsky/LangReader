import XCTest
import LeafReaderCore
@testable import LeafReaderApp

@MainActor
final class VocabularyDocumentWorkIdentityXCTests: XCTestCase {
    func testWorkIdentityRejectsSameDocumentAfterCloseReopen() throws {
        let controller = ReaderWindowController(window: nil)
        let url = URL(fileURLWithPath: "/tmp/vocabulary-work-identity.pdf")
        controller.documentSession.adopt(url: url, kind: .pdf, documentID: "same-document")
        _ = controller.vocabularyState.updateLanguageResolution(.resolved(VocabularyResolvedLanguage(
            id: .english,
            provenance: .automaticDetection
        )))
        let original = try XCTUnwrap(controller.vocabularyDocumentWorkIdentity)

        controller.documentSession.unload()
        controller.documentSession.adopt(url: url, kind: .pdf, documentID: "same-document")

        XCTAssertEqual(controller.currentFileMD5, original.documentID)
        XCTAssertEqual(controller.vocabularyLanguageRevision, original.languageRevision)
        XCTAssertFalse(controller.acceptsVocabularyDocumentWorkIdentity(original))
    }

    func testWorkIdentityRejectsDeferredWebTextGeneration() throws {
        let controller = ReaderWindowController(window: nil)
        let url = URL(fileURLWithPath: "/tmp/vocabulary-work-identity.epub")
        controller.documentSession.adopt(url: url, kind: .epub, documentID: "web-document")
        _ = controller.vocabularyState.updateLanguageResolution(.resolved(VocabularyResolvedLanguage(
            id: .english,
            provenance: .automaticDetection
        )))
        let original = try XCTUnwrap(controller.vocabularyDocumentWorkIdentity)

        controller.documentSession.web.invalidatePlainText()

        XCTAssertEqual(controller.currentFileMD5, original.documentID)
        XCTAssertEqual(controller.documentLoadGeneration, original.loadGeneration)
        XCTAssertEqual(controller.vocabularyLanguageRevision, original.languageRevision)
        XCTAssertFalse(controller.acceptsVocabularyDocumentWorkIdentity(original))
    }
}
