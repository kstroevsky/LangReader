import XCTest

final class ReaderPresentationStateXCTests: XCTestCase {
    func testDefaultTitleIsEmpty() throws {
        try ReaderPresentationStateTests.testDefaultTitleIsEmpty()
    }

    func testSetTitleIsAuthoritative() throws {
        try ReaderPresentationStateTests.testSetTitleIsAuthoritative()
    }

    func testClearResetsTitle() throws {
        try ReaderPresentationStateTests.testClearResetsTitle()
    }

    func testTitleForURLDropsExtension() throws {
        try ReaderPresentationStateTests.testTitleForURLDropsExtension()
    }

    func testTitleForURLIsStableAcrossPaths() throws {
        try ReaderPresentationStateTests.testTitleForURLIsStableAcrossPaths()
    }
}
