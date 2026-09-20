import LeafReaderCore
import XCTest

final class VocabularyAssessmentObservationXCTests: XCTestCase {
    func testObservationDoesNotChangeResultOrFutureQuestionPath() throws {
        let inventory = makeInventory(count: 40)
        var observed = AdaptiveVocabularyAssessment(inventory: inventory, mode: .targetCoverage(0.98))
        var control = observed
        for ordinal in 0..<12 {
            let question = try XCTUnwrap(observed.nextQuestion())
            XCTAssertEqual(question.canonicalKey, control.nextQuestion()?.canonicalKey)
            let evidence: VocabularyKnowledgeEvidence = ordinal.isMultiple(of: 2) ? .verifiedKnown : .reportedUnknown
            observed.record(evidence, for: question.canonicalKey)
            control.record(evidence, for: question.canonicalKey)
        }

        let before = observed.result()
        let snapshot = try observed.validationObservation()
        XCTAssertEqual(snapshot.productionSelection, Set(before.items.filter(\.isSelected).map(\.id)))
        XCTAssertEqual(before, observed.result())
        while !observed.isFinished, !control.isFinished {
            let question = try XCTUnwrap(observed.nextQuestion())
            XCTAssertEqual(question.canonicalKey, control.nextQuestion()?.canonicalKey)
            let evidence: VocabularyKnowledgeEvidence = observed.answeredQuestionCount.isMultiple(of: 2)
                ? .verifiedKnown : .reportedUnknown
            observed.record(evidence, for: question.canonicalKey)
            control.record(evidence, for: question.canonicalKey)
        }
        XCTAssertEqual(observed.answers, control.answers)
        XCTAssertEqual(observed.thetaPosteriorSnapshot, control.thetaPosteriorSnapshot)
        XCTAssertEqual(observed.result(), control.result())
    }

    func testObservationRejectsInvalidPosteriorAndProbability() throws {
        let item = VocabularyAssessmentObservation.Item(
            canonicalKey: "word",
            occurrenceCount: 1,
            isIncluded: true,
            evidence: nil,
            responseCurve: Array(repeating: 0.5, count: 121),
            productionKnownMask: Array(repeating: 0, count: 8)
        )
        XCTAssertThrowsError(try observation(items: [item], posterior: Array(repeating: 0, count: 121))) {
            XCTAssertEqual($0 as? VocabularyAssessmentObservationError, .invalidPosterior)
        }
        let invalid = VocabularyAssessmentObservation.Item(
            canonicalKey: "word",
            occurrenceCount: 1,
            isIncluded: true,
            evidence: nil,
            responseCurve: [Double.nan] + Array(repeating: 0.5, count: 120),
            productionKnownMask: Array(repeating: 0, count: 8)
        )
        XCTAssertThrowsError(try observation(
            items: [invalid], posterior: Array(repeating: 1.0 / 121.0, count: 121)
        )) {
            XCTAssertEqual($0 as? VocabularyAssessmentObservationError, .invalidProbability(key: "word"))
        }
    }

    func testDiagnosticContinuationKeepsHardCeilingAndUniqueness() throws {
        var assessment = AdaptiveVocabularyAssessment(inventory: makeInventory(count: 100), mode: .allUnknown)
        while !assessment.isFinished {
            let question = try XCTUnwrap(assessment.nextQuestion())
            assessment.record(.verifiedKnown, for: question.canonicalKey)
        }
        XCTAssertEqual(assessment.diagnosticNaturalStopReason, .lowExpectedValue)
        XCTAssertLessThan(assessment.answeredQuestionCount, 80)
        while let question = assessment.nextQuestionForDiagnosticContinuation() {
            assessment.record(.verifiedKnown, for: question.canonicalKey)
        }
        XCTAssertEqual(assessment.answeredQuestionCount, 80)
        XCTAssertEqual(Set(assessment.answers.map(\.canonicalKey)).count, assessment.answers.count)
        XCTAssertNil(assessment.nextQuestionForDiagnosticContinuation())
    }

    func testRestoredCommonEvidencePathPreservesMetadataAndPosterior() throws {
        let inventory = makeInventory(count: 40)
        var source = AdaptiveVocabularyAssessment(inventory: inventory, mode: .allUnknown)
        for ordinal in 0..<20 {
            let question = try XCTUnwrap(source.nextQuestion())
            source.record(ordinal.isMultiple(of: 4) ? .reportedUnknown : .verifiedKnown, for: question.canonicalKey)
        }
        let replay = AdaptiveVocabularyAssessment(inventory: inventory, mode: .allUnknown, restoredAnswers: source.answers)
        XCTAssertEqual(replay.answers, source.answers)
        XCTAssertEqual(replay.thetaPosteriorSnapshot, source.thetaPosteriorSnapshot)
        XCTAssertEqual(replay.result(), source.result())
    }

    private func observation(
        items: [VocabularyAssessmentObservation.Item],
        posterior: [Double]
    ) throws -> VocabularyAssessmentObservation {
        try VocabularyAssessmentObservation(
            items: items,
            posterior: posterior,
            epsilonKnowledge: 0.05,
            evidenceReliabilityScale: 1,
            coverageQuantile: 0.05,
            productionSelection: [],
            productionThetaIndexes: Array(repeating: 60, count: 512)
        )
    }

    private func makeInventory(count: Int) -> DocumentVocabularyInventory {
        DocumentVocabularyInventory(
            languageCode: "en",
            candidates: (0..<count).map { index in
                let key = "diagnostic-\(index)"
                return DocumentVocabularyCandidate(
                    canonicalKey: key,
                    displayLemma: key,
                    observedForms: [VocabularyDocumentObservedForm(surface: key, occurrenceCount: count - index)],
                    occurrenceCount: count - index,
                    representativeRange: VocabularyDocumentSourceRange(
                        unitIndex: 0, utf16Location: index, utf16Length: key.utf16.count
                    ),
                    generalFrequencyRank: nil,
                    difficulty: -3 + 6 * Double(index) / Double(max(1, count - 1))
                )
            }
        )
    }
}
