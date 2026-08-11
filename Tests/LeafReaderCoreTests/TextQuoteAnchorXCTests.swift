import Foundation
import XCTest
import LeafReaderCore

final class TextQuoteAnchorXCTests: XCTestCase {
    func testStablePositionResolvesDirectly() throws {
        let source = "before target after"
        let anchor = try XCTUnwrap(TextQuoteAnchor(
            unitOrdinal: 0,
            sourceRange: NSRange(location: 7, length: 6),
            sourceText: source
        ))
        XCTAssertEqual(anchor.resolvedRange(in: source), NSRange(location: 7, length: 6))
    }

    func testExactQuoteRecoveryUsesContextToDisambiguate() throws {
        let source = "alpha before target after omega"
        let anchor = try XCTUnwrap(TextQuoteAnchor(
            unitOrdinal: 0,
            sourceRange: NSRange(location: 13, length: 6),
            sourceText: source
        ))
        let shifted = "target decoy " + source
        XCTAssertEqual(anchor.resolvedRange(in: shifted), NSRange(location: 26, length: 6))
    }

    func testMissingQuoteDoesNotResolve() throws {
        let anchor = try XCTUnwrap(TextQuoteAnchor(
            unitOrdinal: 0,
            sourceRange: NSRange(location: 0, length: 6),
            sourceText: "target"
        ))
        XCTAssertNil(anchor.resolvedRange(in: "different text"))
    }
}
