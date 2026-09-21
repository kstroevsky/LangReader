import Foundation
import XCTest
@testable import LeafReaderValidation

final class VocabularyDiagnosticArtifactsXCTests: XCTestCase {
    func testSemanticDigestMatchesIndependentSHA256Fixture() {
        let bytes = Data("abc".utf8)
        XCTAssertEqual(
            VocabularyDiagnosticArtifacts.sha256(of: bytes),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }
}
