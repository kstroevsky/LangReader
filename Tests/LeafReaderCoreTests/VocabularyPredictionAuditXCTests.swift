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
        XCTAssertEqual(result.fullInferenceCalibration?.itemCount, 4)
        XCTAssertNil(result.directEvidenceOnlyCalibration)
    }

    func testCalibrationMetricsSeparateIdentityUncertaintyFromFullInference() throws {
        let items = [
            VocabularyPredictionAuditItem(
                canonicalKey: "full-known",
                displayLemma: "full-known",
                partOfSpeech: .noun,
                identityPolicy: .fullInference,
                occurrenceCount: 1,
                predictedKnownProbability: 0.9,
                selectedForLearning: false
            ),
            VocabularyPredictionAuditItem(
                canonicalKey: "full-unknown",
                displayLemma: "full-unknown",
                partOfSpeech: .verb,
                identityPolicy: .fullInference,
                occurrenceCount: 1,
                predictedKnownProbability: 0.1,
                selectedForLearning: true
            ),
            VocabularyPredictionAuditItem(
                canonicalKey: "direct-known",
                displayLemma: "direct-known",
                partOfSpeech: .unknown,
                identityPolicy: .directEvidenceOnly,
                occurrenceCount: 1,
                predictedKnownProbability: 0.5,
                selectedForLearning: false
            ),
            VocabularyPredictionAuditItem(
                canonicalKey: "direct-unknown",
                displayLemma: "direct-unknown",
                partOfSpeech: .unknown,
                identityPolicy: .directEvidenceOnly,
                occurrenceCount: 1,
                predictedKnownProbability: 0.5,
                selectedForLearning: true
            )
        ]
        var audit = VocabularyPredictionAuditSession(
            inventoryFingerprint: "mixed-identity",
            languageCode: "en",
            mode: .allUnknown,
            items: items
        )
        audit.record(.known, for: "full-known")
        audit.record(.unknown, for: "full-unknown")
        audit.record(.known, for: "direct-known")
        audit.record(.unknown, for: "direct-unknown")

        let result = try XCTUnwrap(audit.result())
        let full = try XCTUnwrap(result.fullInferenceCalibration)
        let direct = try XCTUnwrap(result.directEvidenceOnlyCalibration)
        XCTAssertEqual(full.itemCount, 2)
        XCTAssertEqual(full.brierScore, 0.01, accuracy: 1e-12)
        XCTAssertEqual(direct.itemCount, 2)
        XCTAssertEqual(direct.brierScore, 0.25, accuracy: 1e-12)
        XCTAssertEqual(direct.expectedCalibrationError, 0, accuracy: 1e-12)
        XCTAssertGreaterThan(result.brierScore, full.brierScore)
    }

    func testLegacyAuditItemDefaultsMissingIdentityPolicyToFullInference() throws {
        let item = VocabularyPredictionAuditItem(
            canonicalKey: "legacy",
            displayLemma: "legacy",
            partOfSpeech: .noun,
            occurrenceCount: 1,
            predictedKnownProbability: 0.5,
            selectedForLearning: false
        )
        let data = try JSONEncoder().encode(item)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "identityPolicy")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        XCTAssertEqual(
            try JSONDecoder().decode(VocabularyPredictionAuditItem.self, from: legacyData).identityPolicy,
            .fullInference
        )
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

    func testAuditCompatibilityUsesExplicitPreparationAlgorithmVersion() {
        let inventory = DocumentVocabularyInventory(
            languageCode: "en",
            candidates: [candidate(0)]
        )
        let prediction = AdaptiveVocabularyAssessment(
            inventory: inventory,
            mode: .allUnknown,
            algorithmVersion: VocabularyPreparationSession.lexicalReconciliationAlgorithmVersion
        ).result()
        let audit = VocabularyPredictionAuditSession(
            inventory: inventory,
            prediction: prediction,
            mode: .allUnknown,
            algorithmVersion: VocabularyPreparationSession.lexicalReconciliationAlgorithmVersion
        )

        XCTAssertEqual(
            audit.assessmentAlgorithmVersion,
            VocabularyPreparationSession.lexicalReconciliationAlgorithmVersion
        )
        XCTAssertTrue(audit.isCompatible(
            inventory: inventory,
            mode: .allUnknown,
            algorithmVersion: VocabularyPreparationSession.lexicalReconciliationAlgorithmVersion
        ))
        XCTAssertFalse(audit.isCompatible(
            inventory: inventory,
            mode: .allUnknown,
            algorithmVersion: VocabularyPreparationSession.currentAlgorithmVersion
        ))
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
