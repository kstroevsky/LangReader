import XCTest
import LeafReaderCore

final class AdaptiveVocabularyAssessmentXCTests: XCTestCase {
    func testDifficultyMapsRankPercentileAndMissingRankToHardestPrior() {
        XCTAssertEqual(DocumentVocabularyInventory.difficulty(forRank: nil, maximumRank: 200_000), 4)
        XCTAssertEqual(DocumentVocabularyInventory.difficulty(forRank: 1, maximumRank: 200_000), -4)
        XCTAssertEqual(DocumentVocabularyInventory.difficulty(forRank: 100_000, maximumRank: 200_000), 0, accuracy: 0.000_001)
        XCTAssertEqual(DocumentVocabularyInventory.difficulty(forRank: 200_000, maximumRank: 200_000), 4)
    }

    func testFirstEightQuestionsSpanAvailableDifficultyOctilesDeterministically() throws {
        var assessment = AdaptiveVocabularyAssessment(
            inventory: inventory(count: 80),
            mode: .allUnknown
        )
        var askedDifficulties: [Double] = []
        for _ in 0..<8 {
            let question = try XCTUnwrap(assessment.nextQuestion())
            askedDifficulties.append(question.difficulty)
            assessment.record(.known, for: question.canonicalKey)
        }

        XCTAssertEqual(Set(askedDifficulties).count, 8)
        XCTAssertLessThan(askedDifficulties.first ?? 0, -2.5)
        XCTAssertGreaterThan(askedDifficulties.last ?? 0, 2.5)
    }

    func testDirectAnswersOverridePosteriorClassification() throws {
        let inventory = inventory(count: 24)
        var assessment = AdaptiveVocabularyAssessment(inventory: inventory, mode: .allUnknown)
        let known = try XCTUnwrap(assessment.nextQuestion())
        assessment.record(.known, for: known.canonicalKey)
        let unknown = try XCTUnwrap(assessment.nextQuestion())
        assessment.record(.unknown, for: unknown.canonicalKey)

        let result = assessment.result()
        XCTAssertEqual(result.items.first { $0.id == known.id }?.classification, .confirmedKnown)
        XCTAssertEqual(result.items.first { $0.id == known.id }?.knownProbability, 1)
        XCTAssertEqual(result.items.first { $0.id == unknown.id }?.classification, .confirmedUnknown)
        XCTAssertEqual(result.items.first { $0.id == unknown.id }?.knownProbability, 0)
    }

    func testExcludedItemDoesNotConsumeAnsweredQuestionSlot() throws {
        var assessment = AdaptiveVocabularyAssessment(inventory: inventory(count: 24), mode: .allUnknown)
        let question = try XCTUnwrap(assessment.nextQuestion())
        assessment.record(.excluded, for: question.canonicalKey)

        XCTAssertEqual(assessment.answeredQuestionCount, 0)
        XCTAssertEqual(assessment.result().items.first { $0.id == question.id }?.classification, .excluded)
    }

    func testDeferredDefinitionFailureDoesNotConsumeOrExcludeQuestion() throws {
        var assessment = AdaptiveVocabularyAssessment(inventory: inventory(count: 24), mode: .allUnknown)
        let deferred = try XCTUnwrap(assessment.nextQuestion())
        assessment.skipCurrentQuestion()
        let next = try XCTUnwrap(assessment.nextQuestion())

        XCTAssertNotEqual(next.id, deferred.id)
        XCTAssertEqual(assessment.answeredQuestionCount, 0)
        XCTAssertNotEqual(assessment.result().items.first { $0.id == deferred.id }?.classification, .excluded)
    }

    func testCoverageModeChoosesSmallestHighImpactDeckToReachTarget() {
        let candidates = [
            candidate(key: "frequent", difficulty: 4, count: 80),
            candidate(key: "rare-a", difficulty: 4, count: 10),
            candidate(key: "rare-b", difficulty: 4, count: 10)
        ]
        let assessment = AdaptiveVocabularyAssessment(
            inventory: DocumentVocabularyInventory(languageCode: "en", candidates: candidates),
            mode: .targetCoverage(0.80)
        )

        let selected = assessment.result().items.filter(\.isSelected).map(\.id)
        XCTAssertEqual(selected, ["frequent"])
        XCTAssertGreaterThanOrEqual(assessment.result().expectedCoverageAfterSelection, 0.80)
    }

    func testAllUnknownModeSelectsConfirmedUnknownAndLowPosteriorItems() throws {
        var assessment = AdaptiveVocabularyAssessment(inventory: inventory(count: 24), mode: .allUnknown)
        let question = try XCTUnwrap(assessment.nextQuestion())
        assessment.record(.unknown, for: question.canonicalKey)

        let result = assessment.result()
        XCTAssertTrue(result.items.first { $0.id == question.id }?.isSelected == true)
        XCTAssertTrue(result.items.filter { $0.knownProbability < 0.5 && $0.classification != .excluded }.allSatisfy(\.isSelected))
    }

    func testTailValidationContradictionRaisesCappedErrorFloor() throws {
        var assessment = AdaptiveVocabularyAssessment(inventory: inventory(count: 60), mode: .allUnknown)
        for _ in 0..<14 {
            let question = try XCTUnwrap(assessment.nextQuestion())
            assessment.record(.known, for: question.canonicalKey)
        }
        let validation = try XCTUnwrap(assessment.nextQuestion())
        assessment.record(.unknown, for: validation.canonicalKey)

        XCTAssertGreaterThan(assessment.errorFloor, 0.05)
        XCTAssertLessThanOrEqual(assessment.errorFloor, 0.25)
    }

    private func inventory(count: Int) -> DocumentVocabularyInventory {
        let candidates = (0..<count).map { index in
            candidate(
                key: String(format: "word-%03d", index),
                difficulty: -4 + (8 * Double(index) / Double(max(1, count - 1))),
                count: (index % 5) + 1
            )
        }
        return DocumentVocabularyInventory(languageCode: "en", candidates: candidates)
    }

    private func candidate(key: String, difficulty: Double, count: Int) -> DocumentVocabularyCandidate {
        DocumentVocabularyCandidate(
            canonicalKey: key,
            displayLemma: key,
            observedForms: [VocabularyDocumentObservedForm(surface: key, occurrenceCount: count)],
            occurrenceCount: count,
            representativeRange: VocabularyDocumentSourceRange(unitIndex: 0, utf16Location: 0, utf16Length: key.utf16.count),
            generalFrequencyRank: nil,
            difficulty: difficulty
        )
    }
}
