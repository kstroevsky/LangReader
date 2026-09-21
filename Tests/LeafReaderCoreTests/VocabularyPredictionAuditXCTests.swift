import XCTest
import LeafReaderCore

final class VocabularyPredictionAuditXCTests: XCTestCase {
    func testColdStartAuditIncludesEveryLemmaInDeterministicBlindOrder() {
        let inventory = DocumentVocabularyInventory(
            languageCode: "en",
            candidates: (0..<12).map(candidate)
        )
        let prediction = AdaptiveVocabularyAssessment(
            inventory: inventory,
            mode: .allUnknown
        ).result()
        let first = VocabularyPredictionAuditSession(
            inventory: inventory,
            prediction: prediction,
            mode: .allUnknown
        )
        let second = VocabularyPredictionAuditSession(
            inventory: inventory,
            prediction: prediction,
            mode: .allUnknown
        )

        XCTAssertEqual(first.items, second.items)
        XCTAssertEqual(Set(first.items.map(\.canonicalKey)), Set(inventory.candidates.map(\.canonicalKey)))
        XCTAssertEqual(first.answeredCount, 0)
        XCTAssertEqual(first.totalCount, inventory.candidates.count)
        XCTAssertFalse(first.isComplete)
        XCTAssertNotNil(first.nextItem)
    }

    func testCompleteAuditReportsExactPersonalPredictionErrorsAndCoverage() throws {
        let items = [
            VocabularyPredictionAuditItem(
                canonicalKey: "selected-unknown",
                displayLemma: "selected-unknown",
                partOfSpeech: .noun,
                occurrenceCount: 4,
                predictedKnownProbability: 0.2,
                selectedForLearning: true
            ),
            VocabularyPredictionAuditItem(
                canonicalKey: "selected-known",
                displayLemma: "selected-known",
                partOfSpeech: .verb,
                occurrenceCount: 1,
                predictedKnownProbability: 0.3,
                selectedForLearning: true
            ),
            VocabularyPredictionAuditItem(
                canonicalKey: "missed-unknown",
                displayLemma: "missed-unknown",
                partOfSpeech: .adjective,
                occurrenceCount: 5,
                predictedKnownProbability: 0.9,
                selectedForLearning: false
            ),
            VocabularyPredictionAuditItem(
                canonicalKey: "predicted-known",
                displayLemma: "predicted-known",
                partOfSpeech: .noun,
                occurrenceCount: 10,
                predictedKnownProbability: 0.8,
                selectedForLearning: false
            )
        ]
        var audit = VocabularyPredictionAuditSession(
            inventoryFingerprint: "fixture",
            languageCode: "en",
            mode: .allUnknown,
            items: items
        )
        audit.record(.unknown, for: "selected-unknown")
        audit.record(.known, for: "selected-known")
        audit.record(.unknown, for: "missed-unknown")
        audit.record(.known, for: "predicted-known")

        let result = try XCTUnwrap(audit.result())
        XCTAssertEqual(result.predictedLearningCount, 2)
        XCTAssertEqual(result.actualUnknownCount, 2)
        XCTAssertEqual(result.predictedLearningPrecision, 0.5, accuracy: 1e-12)
        XCTAssertEqual(result.predictedLearningRecall, 0.5, accuracy: 1e-12)
        XCTAssertEqual(result.missedUnknownCount, 1)
        XCTAssertEqual(result.currentLexicalTokenCoverage, 0.55, accuracy: 1e-12)
        XCTAssertEqual(result.projectedLexicalTokenCoverage, 0.75, accuracy: 1e-12)
        XCTAssertEqual(result.brierScore, 0.345, accuracy: 1e-12)
        XCTAssertEqual(result.expectedCalibrationError, 0.5, accuracy: 1e-12)
    }

    func testPreparationSessionRoundTripsIncompleteAudit() throws {
        var audit = VocabularyPredictionAuditSession(
            inventoryFingerprint: "fixture",
            languageCode: "de",
            mode: .targetCoverage(0.98),
            items: [VocabularyPredictionAuditItem(
                canonicalKey: "wort",
                displayLemma: "Wort",
                partOfSpeech: .noun,
                occurrenceCount: 2,
                predictedKnownProbability: 0.4,
                selectedForLearning: true
            )]
        )
        audit.record(.unknown, for: "wort")
        let session = VocabularyPreparationSession(predictionAudit: audit)

        let data = try JSONEncoder().encode(session)
        XCTAssertEqual(try JSONDecoder().decode(VocabularyPreparationSession.self, from: data), session)
    }

    private func candidate(_ index: Int) -> DocumentVocabularyCandidate {
        let lemma = "word-\(index)"
        return DocumentVocabularyCandidate(
            canonicalKey: lemma,
            displayLemma: lemma,
            partOfSpeech: index.isMultiple(of: 2) ? .noun : .verb,
            observedForms: [VocabularyDocumentObservedForm(surface: lemma, occurrenceCount: index + 1)],
            occurrenceCount: index + 1,
            representativeRange: VocabularyDocumentSourceRange(
                unitIndex: 0,
                utf16Location: index * 10,
                utf16Length: lemma.utf16.count
            ),
            generalFrequencyRank: nil,
            difficulty: -2 + Double(index) * 0.4
        )
    }
}
