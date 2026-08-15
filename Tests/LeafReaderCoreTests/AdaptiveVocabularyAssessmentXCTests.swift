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
        XCTAssertEqual(selected, ["frequent", "rare-a"])
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
        XCTAssertEqual(assessment.errorFloor, 2.0 / 21.0, accuracy: 0.000_001)
    }

    func testCoverageLowerBoundPreservesDirectAnswers() {
        let candidates = [
            candidate(key: "known", difficulty: 4, count: 50),
            candidate(key: "unknown", difficulty: -4, count: 30),
            candidate(key: "unasked", difficulty: 0, count: 20)
        ]
        var assessment = AdaptiveVocabularyAssessment(
            inventory: DocumentVocabularyInventory(languageCode: "en", candidates: candidates),
            mode: .targetCoverage(0.98)
        )
        assessment.record(.known, for: "known")
        assessment.record(.unknown, for: "unknown")

        let result = assessment.result(selectionOverride: [])
        let lowerTheta = result.diagnostics.thetaLowerBound
        let unaskedProbability = assessment.errorFloor
            + (1 - 2 * assessment.errorFloor) / (1 + exp(-(lowerTheta - 0)))
        let variance = 20.0 * 20.0 * unaskedProbability * (1 - unaskedProbability)
        let expected = (50 + 20 * unaskedProbability - 1.644_853_626_951_47 * sqrt(variance)) / 100

        XCTAssertEqual(result.diagnostics.conservativeCoverageLowerBound, expected, accuracy: 0.000_001)
        XCTAssertEqual(result.items.first { $0.id == "known" }?.knownProbability, 1)
        XCTAssertEqual(result.items.first { $0.id == "unknown" }?.knownProbability, 0)
    }

    func testApplyingSelectionRecomputesConservativeCoverage() {
        let candidates = [
            candidate(key: "known", difficulty: 0, count: 60),
            candidate(key: "unknown", difficulty: 0, count: 40)
        ]
        var assessment = AdaptiveVocabularyAssessment(
            inventory: DocumentVocabularyInventory(languageCode: "en", candidates: candidates),
            mode: .targetCoverage(0.98)
        )
        assessment.record(.known, for: "known")
        assessment.record(.unknown, for: "unknown")

        let withoutDeck = assessment.result(selectionOverride: [])
        let withDeck = withoutDeck.applyingSelection(["unknown"])

        XCTAssertEqual(withoutDeck.diagnostics.conservativeCoverageLowerBound, 0.6, accuracy: 0.000_001)
        XCTAssertEqual(withDeck.diagnostics.conservativeCoverageLowerBound, 1, accuracy: 0.000_001)
    }

    func testSkippingEveryCandidateFinishesAsExhaustedWithoutAnswers() throws {
        var assessment = AdaptiveVocabularyAssessment(inventory: inventory(count: 5), mode: .allUnknown)
        for _ in 0..<5 {
            _ = try XCTUnwrap(assessment.nextQuestion())
            assessment.skipCurrentQuestion()
        }

        XCTAssertTrue(assessment.isFinished)
        XCTAssertNil(assessment.nextQuestion())
        XCTAssertEqual(assessment.answeredQuestionCount, 0)
        XCTAssertEqual(assessment.result().diagnostics.skippedQuestionCount, 5)
        XCTAssertEqual(assessment.result().diagnostics.stopReason, .exhaustedCandidates)
    }

    func testQuestionLimitIsAlwaysEightyAnswers() {
        let inventory = inventory(count: 100)
        var assessment = AdaptiveVocabularyAssessment(inventory: inventory, mode: .allUnknown)
        for candidate in inventory.candidates.prefix(80) {
            assessment.record(.known, for: candidate.canonicalKey)
        }

        XCTAssertTrue(assessment.isFinished)
        XCTAssertEqual(assessment.result().diagnostics.stopReason, .questionLimit)
        XCTAssertTrue(assessment.result().reachedQuestionLimit)
    }

    func testExcludedSelectionCannotReenterCoverageDenominator() throws {
        let inventory = DocumentVocabularyInventory(
            languageCode: "en",
            candidates: [candidate(key: "noise", difficulty: 0, count: 100)]
        )
        var assessment = AdaptiveVocabularyAssessment(inventory: inventory, mode: .targetCoverage(0.98))
        assessment.record(.excluded, for: "noise")

        let result = assessment.result(selectionOverride: ["noise"])
        XCTAssertFalse(try XCTUnwrap(result.items.first).isSelected)
        XCTAssertEqual(result.expectedCoverageAfterSelection, 1)
        XCTAssertEqual(result.diagnostics.conservativeCoverageLowerBound, 1)
    }

    func testAllUnknownStopsAfterThreeLowValueSelections() throws {
        var assessment = AdaptiveVocabularyAssessment(inventory: inventory(count: 60), mode: .allUnknown)
        while !assessment.isFinished {
            let question = try XCTUnwrap(assessment.nextQuestion())
            assessment.record(.known, for: question.canonicalKey)
        }

        XCTAssertGreaterThanOrEqual(assessment.answeredQuestionCount, 20)
        XCTAssertLessThan(assessment.answeredQuestionCount, 80)
        XCTAssertEqual(assessment.result().diagnostics.stopReason, .lowExpectedValue)
    }

    func testCoverageStopsOnlyAfterStableDeckAndLowerBound() throws {
        let candidates = (0..<60).map { index in
            candidate(key: String(format: "easy-%03d", index), difficulty: -4, count: 1)
        }
        var assessment = AdaptiveVocabularyAssessment(
            inventory: DocumentVocabularyInventory(languageCode: "en", candidates: candidates),
            mode: .targetCoverage(0.98)
        )
        while !assessment.isFinished {
            let question = try XCTUnwrap(assessment.nextQuestion())
            assessment.record(.known, for: question.canonicalKey)
        }

        let result = assessment.result()
        XCTAssertGreaterThanOrEqual(assessment.answeredQuestionCount, 23)
        XCTAssertEqual(result.diagnostics.stopReason, .targetCoverageStable)
        XCTAssertGreaterThanOrEqual(result.diagnostics.conservativeCoverageLowerBound, 0.98)
    }

    func testValidationQuestionsBeginAtFifteenAndAlternateTails() throws {
        var assessment = AdaptiveVocabularyAssessment(inventory: inventory(count: 80), mode: .allUnknown)
        for questionNumber in 1...20 {
            let question = try XCTUnwrap(assessment.nextQuestion())
            assessment.record(questionNumber.isMultiple(of: 2) ? .known : .unknown, for: question.canonicalKey)
            let answer = try XCTUnwrap(assessment.answers.last)
            XCTAssertEqual(answer.wasValidation, questionNumber == 15 || questionNumber == 20)
        }

        let validations = assessment.answers.filter(\.wasValidation)
        XCTAssertEqual(validations.count, 2)
        XCTAssertNotEqual(validations[0].predictedKnown, validations[1].predictedKnown)
    }

    func testRestoredDirectAnswersRecomputeSamePosterior() throws {
        let inventory = inventory(count: 40)
        var original = AdaptiveVocabularyAssessment(inventory: inventory, mode: .allUnknown)
        for index in 0..<12 {
            let question = try XCTUnwrap(original.nextQuestion())
            original.record(index.isMultiple(of: 3) ? .unknown : .known, for: question.canonicalKey)
        }
        let restored = AdaptiveVocabularyAssessment(
            inventory: inventory,
            mode: .allUnknown,
            restoredAnswers: original.answers
        )

        for candidate in inventory.candidates {
            let restoredProbability = try XCTUnwrap(restored.knownProbability(for: candidate.canonicalKey))
            let originalProbability = try XCTUnwrap(original.knownProbability(for: candidate.canonicalKey))
            XCTAssertEqual(
                restoredProbability,
                originalProbability,
                accuracy: 0.000_000_1
            )
        }
        XCTAssertEqual(restored.result().diagnostics.estimatedTheta, original.result().diagnostics.estimatedTheta, accuracy: 0.000_000_1)
    }

    func testAdaptiveChoiceMaximizesExpectedLossReduction() throws {
        let inventory = inventory(count: 12)
        var assessment = AdaptiveVocabularyAssessment(inventory: inventory, mode: .allUnknown)
        for index in 0..<8 {
            let question = try XCTUnwrap(assessment.nextQuestion())
            assessment.record(index.isMultiple(of: 2) ? .known : .unknown, for: question.canonicalKey)
        }

        let scored = inventory.candidates.compactMap { candidate -> (String, Double)? in
            assessment.expectedLossReduction(for: candidate.canonicalKey).map { (candidate.canonicalKey, $0) }
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0 < $1.0
        }
        let selected = try XCTUnwrap(assessment.nextQuestion())

        XCTAssertEqual(selected.canonicalKey, try XCTUnwrap(scored.first).0)
    }

    func testCoverageDeckHasMinimumCardinalityAgainstBruteForceOracle() {
        let candidates = [
            candidate(key: "a", difficulty: -2, count: 40),
            candidate(key: "b", difficulty: 0, count: 25),
            candidate(key: "c", difficulty: 1, count: 20),
            candidate(key: "d", difficulty: 2, count: 10),
            candidate(key: "e", difficulty: 4, count: 5)
        ]
        let assessment = AdaptiveVocabularyAssessment(
            inventory: DocumentVocabularyInventory(languageCode: "en", candidates: candidates),
            mode: .targetCoverage(0.90)
        )
        let result = assessment.result()
        let selected = Set(result.items.filter(\.isSelected).map(\.id))

        func reachesTarget(_ keys: Set<String>) -> Bool {
            result.applyingSelection(keys).diagnostics.conservativeCoverageLowerBound >= 0.90
        }

        var oracleMinimum = candidates.count
        for mask in 0..<(1 << candidates.count) {
            let keys = Set(candidates.indices.compactMap { index in
                mask & (1 << index) == 0 ? nil : candidates[index].canonicalKey
            })
            if reachesTarget(keys) { oracleMinimum = min(oracleMinimum, keys.count) }
        }

        XCTAssertTrue(reachesTarget(selected))
        XCTAssertEqual(selected.count, oracleMinimum)
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
