import Foundation
import LeafReaderCore
import XCTest
@testable import LeafReaderValidation

final class ValidationBoundaryXCTests: XCTestCase {
    func testValidationTargetLinksCoreWithoutApp() {
        let mode = VocabularyAssessmentMode.allUnknown
        XCTAssertEqual(mode, .allUnknown)
    }

    func testPOSEvaluatorRejectsUnresolvedLanguageInsteadOfRoutingAsEnglish() throws {
        let fixture = """
        {
          "schemaVersion": 1,
          "fixtureID": "invalid-language",
          "release": "test",
          "cases": [
            {
              "caseID": "undetermined-language",
              "sourceID": "test",
              "sourceSentenceID": "sentence-1",
              "languageCode": "und",
              "text": "word",
              "surface": "word",
              "goldLemma": "word",
              "goldUPOS": "NOUN",
              "goldXPOS": "",
              "goldFeatures": "",
              "occurrenceWeight": 1
            }
          ]
        }
        """

        XCTAssertThrowsError(try evaluateVocabularyPOSFixture(Data(fixture.utf8)))
    }
}
