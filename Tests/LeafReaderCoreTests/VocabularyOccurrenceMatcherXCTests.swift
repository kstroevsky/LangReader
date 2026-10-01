import XCTest
@testable import LeafReaderCore

final class VocabularyOccurrenceMatcherXCTests: XCTestCase {
    func testDocumentExactFormDiscoveryPreservesPageOrderWithoutLanguage() throws {
        let pages = [
            "Prima appears once.",
            "Nothing on this page.",
            "Prima appears twice: prima."
        ]

        let matches = try XCTUnwrap(
            VocabularyOccurrenceMatcher.matches(query: "Prima", inTexts: pages)
        )

        XCTAssertEqual(matches.map(\.count), [1, 0, 2])
        XCTAssertEqual(matches[0].map(\.matchedText), ["Prima"])
        XCTAssertEqual(matches[2].map(\.matchedText), ["Prima", "prima"])
    }

    func testDocumentExactFormDiscoveryReturnsNilWhenCancelled() {
        let pages = Array(repeating: "word appears here", count: 4)
        var checks = 0

        let matches = VocabularyOccurrenceMatcher.matches(
            query: "word",
            inTexts: pages,
            isCancelled: {
                checks += 1
                return checks > 2
            }
        )

        XCTAssertNil(matches)
    }
}
