import LeafReaderCore
import XCTest
@testable import LeafReaderValidation

final class ValidationBoundaryXCTests: XCTestCase {
    func testValidationTargetLinksCoreWithoutApp() {
        let mode = VocabularyAssessmentMode.allUnknown
        XCTAssertEqual(mode, .allUnknown)
    }
}
