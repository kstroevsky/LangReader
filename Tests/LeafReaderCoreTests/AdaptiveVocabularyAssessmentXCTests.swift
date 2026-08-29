import XCTest
import LeafReaderCore

final class AdaptiveVocabularyAssessmentXCTests: XCTestCase {
    func testDifficultyMapsRankPercentileAndMissingRankToHardestPrior() {
        XCTAssertEqual(DocumentVocabularyInventory.difficulty(forRank: nil, maximumRank: 200_000), 4)
        XCTAssertEqual(DocumentVocabularyInventory.difficulty(forRank: 1, maximumRank: 200_000), -4)
        XCTAssertEqual(DocumentVocabularyInventory.difficulty(forRank: 100_000, maximumRank: 200_000), 0, accuracy: 0.000_001)
        XCTAssertEqual(DocumentVocabularyInventory.difficulty(forRank: 200_000, maximumRank: 200_000), 4)
    }

    func testFrequencyDifficultyPriorCarriesRankDependentUncertainty() {
        let scale = VocabularyFrequencyScale(sourceID: "fixture", version: "v1", maximumRank: 200_000)
        let common = VocabularyItemDifficultyPrior.frequencyRank(1, scale: scale)
        let rare = VocabularyItemDifficultyPrior.frequencyRank(190_000, scale: scale)
        let missing = VocabularyItemDifficultyPrior.frequencyRank(nil, scale: scale)

        XCTAssertEqual(common.source, .rankedFrequency)
        XCTAssertEqual(common.standardDeviation, 0.350_04, accuracy: 0.000_01)
        XCTAssertGreaterThan(rare.standardDeviation, common.standardDeviation)
        XCTAssertEqual(missing.mean, 4)
        XCTAssertEqual(missing.standardDeviation, 1.5)
        XCTAssertEqual(missing.source, .unrankedFrequency)
    }

    func testPosteriorPredictiveCoverageIsDeterministicForInventoryIdentity() {
        let inventory = inventory(count: 5)
        let first = AdaptiveVocabularyAssessment(
            inventory: inventory,
            mode: .targetCoverage(0.98)
        ).result()
        let second = AdaptiveVocabularyAssessment(
            inventory: inventory,
            mode: .targetCoverage(0.98)
        ).result()

        XCTAssertEqual(first.diagnostics.conservativeCoverageLowerBound, second.diagnostics.conservativeCoverageLowerBound)
        XCTAssertEqual(first.items.map(\.predictiveKnownMask), second.items.map(\.predictiveKnownMask))
        XCTAssertEqual(first.items.map(\.isSelected), second.items.map(\.isSelected))
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

    func testVerifiedAndReportedEvidenceRemainStrongButFallible() throws {
        let inventory = inventory(count: 24)
        var assessment = AdaptiveVocabularyAssessment(inventory: inventory, mode: .allUnknown)
        let known = try XCTUnwrap(assessment.nextQuestion())
        assessment.record(.known, for: known.canonicalKey)
        let unknown = try XCTUnwrap(assessment.nextQuestion())
        assessment.record(.unknown, for: unknown.canonicalKey)

        let result = assessment.result()
        let knownItem = try XCTUnwrap(result.items.first { $0.id == known.id })
        let unknownItem = try XCTUnwrap(result.items.first { $0.id == unknown.id })
        XCTAssertEqual(knownItem.classification, .verifiedKnown)
        XCTAssertGreaterThan(knownItem.knownProbability, 0.5)
        XCTAssertLessThan(knownItem.knownProbability, 1)
        XCTAssertEqual(unknownItem.classification, .reportedUnknown)
        XCTAssertGreaterThan(unknownItem.knownProbability, 0)
        XCTAssertLessThan(unknownItem.knownProbability, 0.5)
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

    func testTailValidationContradictionRaisesOnlyCappedKnowledgeMismatch() throws {
        var assessment = AdaptiveVocabularyAssessment(inventory: inventory(count: 60), mode: .allUnknown)
        for _ in 0..<14 {
            let question = try XCTUnwrap(assessment.nextQuestion())
            assessment.record(.known, for: question.canonicalKey)
        }
        let validation = try XCTUnwrap(assessment.nextQuestion())
        assessment.record(.unknown, for: validation.canonicalKey)

        XCTAssertGreaterThan(assessment.epsilonKnowledge, 0.05)
        XCTAssertLessThanOrEqual(assessment.epsilonKnowledge, 0.25)
        XCTAssertEqual(assessment.epsilonKnowledge, 2.0 / 21.0, accuracy: 0.000_001)
        XCTAssertEqual(assessment.errorFloor, assessment.epsilonKnowledge)
        XCTAssertEqual(
            VocabularyObservationModel.emission(for: .verifiedKnown)?.reliability,
            0.97
        )
    }

    func testDiagnosticConfigurationDoesNotReplaceProductionDefaults() {
        let configuration = VocabularyAssessmentModelConfiguration(
            evidenceReliabilityScale: 0.8,
            minimumEpsilonKnowledge: 0.10,
            coverageQuantile: 0.10,
            warmPriorWeight: 0.75
        )
        let diagnostic = AdaptiveVocabularyAssessment(
            inventory: inventory(count: 5),
            mode: .targetCoverage(0.98),
            modelConfiguration: configuration
        )
        let production = AdaptiveVocabularyAssessment(
            inventory: inventory(count: 5),
            mode: .targetCoverage(0.98)
        )

        XCTAssertEqual(diagnostic.epsilonKnowledge, 0.10)
        XCTAssertEqual(diagnostic.result().coverageQuantile, 0.10)
        XCTAssertEqual(production.epsilonKnowledge, 0.05)
        XCTAssertEqual(production.result().coverageQuantile, 0.05)
    }

    func testDiagnosticCoverageQuantileUsesTheSamePredictiveSamplesMonotonically() {
        let inventory = inventory(count: 60)
        let low = AdaptiveVocabularyAssessment(
            inventory: inventory,
            mode: .targetCoverage(0.98),
            modelConfiguration: VocabularyAssessmentModelConfiguration(coverageQuantile: 0.025)
        ).result(selectionOverride: [])
        let high = AdaptiveVocabularyAssessment(
            inventory: inventory,
            mode: .targetCoverage(0.98),
            modelConfiguration: VocabularyAssessmentModelConfiguration(coverageQuantile: 0.10)
        ).result(selectionOverride: [])

        XCTAssertGreaterThanOrEqual(
            high.diagnostics.conservativeCoverageLowerBound,
            low.diagnostics.conservativeCoverageLowerBound
        )
        XCTAssertNotEqual(
            high.diagnostics.conservativeCoverageLowerBound,
            low.diagnostics.conservativeCoverageLowerBound
        )
    }

    func testCoverageLowerBoundPreservesSoftEvidence() throws {
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
        let knownProbability = try XCTUnwrap(result.items.first { $0.id == "known" }?.knownProbability)
        let unknownProbability = try XCTUnwrap(result.items.first { $0.id == "unknown" }?.knownProbability)
        XCTAssertGreaterThan(knownProbability, 0.5)
        XCTAssertLessThan(knownProbability, 1)
        XCTAssertGreaterThan(unknownProbability, 0)
        XCTAssertLessThan(unknownProbability, 0.5)
        XCTAssertGreaterThanOrEqual(result.diagnostics.conservativeCoverageLowerBound, 0)
        XCTAssertLessThanOrEqual(result.diagnostics.conservativeCoverageLowerBound, 1)
    }

    func testEvidenceStrengthOrdersAnsweredProbabilities() throws {
        let inventory = DocumentVocabularyInventory(
            languageCode: "en",
            candidates: [
                candidate(key: "verified", difficulty: 0, count: 1),
                candidate(key: "legacy", difficulty: 0, count: 1),
                candidate(key: "unsure", difficulty: 0, count: 1),
                candidate(key: "reported", difficulty: 0, count: 1)
            ]
        )
        var assessment = AdaptiveVocabularyAssessment(inventory: inventory, mode: .allUnknown)
        assessment.record(.verifiedKnown, for: "verified")
        assessment.record(.legacyKnown, for: "legacy")
        assessment.record(.unsure, for: "unsure")
        assessment.record(.reportedUnknown, for: "reported")

        let verified = try XCTUnwrap(assessment.knownProbability(for: "verified"))
        let legacy = try XCTUnwrap(assessment.knownProbability(for: "legacy"))
        let unsure = try XCTUnwrap(assessment.knownProbability(for: "unsure"))
        let reported = try XCTUnwrap(assessment.knownProbability(for: "reported"))
        XCTAssertGreaterThan(verified, legacy)
        XCTAssertGreaterThan(legacy, unsure)
        XCTAssertGreaterThan(unsure, reported)
    }

    func testLegacyOutcomePayloadMigratesToWeakEvidence() throws {
        let data = Data(#"{"canonicalKey":"gaunt","outcome":"known","wasValidation":false}"#.utf8)
        let answer = try JSONDecoder().decode(VocabularyAssessmentAnswer.self, from: data)

        XCTAssertEqual(answer.evidence, .legacyKnown)
        XCTAssertNil(answer.typedMeaning)
        let encoded = try JSONEncoder().encode(answer)
        XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains("legacyKnown"))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("outcome"))
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

        XCTAssertLessThan(withoutDeck.diagnostics.conservativeCoverageLowerBound, 1)
        XCTAssertGreaterThan(
            withDeck.diagnostics.conservativeCoverageLowerBound,
            withoutDeck.diagnostics.conservativeCoverageLowerBound
        )
        XCTAssertLessThan(withDeck.diagnostics.conservativeCoverageLowerBound, 1)
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
        XCTAssertGreaterThanOrEqual(assessment.answeredQuestionCount, 20)
        XCTAssertTrue(
            result.diagnostics.stopReason == .targetCoverageStable
                || result.diagnostics.stopReason == .exhaustedCandidates
        )
        XCTAssertGreaterThanOrEqual(result.diagnostics.conservativeCoverageLowerBound, 0.98)
    }

    func testValidationQuestionsBeginAtFifteenAndAlternateTails() throws {
        var assessment = AdaptiveVocabularyAssessment(inventory: inventory(count: 80), mode: .allUnknown)
        for questionNumber in 1...20 {
            let question = try XCTUnwrap(assessment.nextQuestion())
            assessment.record(questionNumber.isMultiple(of: 2) ? .known : .unknown, for: question.canonicalKey)
            let answer = try XCTUnwrap(assessment.answers.last)
            XCTAssertEqual(answer.wasValidation, questionNumber == 15 || questionNumber == 20)
            XCTAssertEqual(answer.questionOrdinal, questionNumber)
            XCTAssertEqual(
                answer.selectionType,
                questionNumber <= 8
                    ? .initialCalibration
                    : (questionNumber == 15 || questionNumber == 20 ? .tailValidation : .adaptiveLoss)
            )
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(answer.predictedKnownBeforeAnswer), 0)
            XCTAssertLessThanOrEqual(try XCTUnwrap(answer.predictedKnownBeforeAnswer), 1)
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

    func testLargeCoverageDeckDeletionPassIsLocallyMinimal() {
        let assessment = AdaptiveVocabularyAssessment(
            inventory: inventory(count: 20),
            mode: .targetCoverage(0.98)
        )
        let result = assessment.result()
        let selected = Set(result.items.filter(\.isSelected).map(\.id))

        XCTAssertGreaterThanOrEqual(result.diagnostics.conservativeCoverageLowerBound, 0.98)
        for key in selected {
            XCTAssertLessThan(
                result.applyingSelection(selected.subtracting([key]))
                    .diagnostics.conservativeCoverageLowerBound,
                0.98
            )
        }
    }

    func testWarmPriorNeedsTwoCurrentTailValidationsBeforeEightQuestionMinimum() throws {
        let prior = VocabularyReaderPrior(
            languageCode: "en",
            thetaPosterior: Array(repeating: 1.0 / 121.0, count: 121),
            completedSessionCount: 2,
            verifiedEvidenceCount: 40,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_000),
            algorithmVersion: 3
        )
        var assessment = AdaptiveVocabularyAssessment(
            inventory: inventory(count: 40),
            mode: .allUnknown,
            readerPrior: prior,
            currentDate: Date(timeIntervalSince1970: 1_001)
        )
        XCTAssertTrue(assessment.usedEligibleReaderPrior)
        XCTAssertEqual(assessment.requiredMinimumAnsweredQuestionCount, 20)

        for _ in 0..<8 {
            let question = try XCTUnwrap(assessment.nextQuestion())
            assessment.record(.verifiedKnown, for: question.canonicalKey)
        }
        XCTAssertEqual(assessment.answers.filter(\.wasValidation).count, 2)
        XCTAssertEqual(assessment.requiredMinimumAnsweredQuestionCount, 8)
    }

    func testEligibleWarmPriorMateriallyReducesCoverageQuestionCount() throws {
        let inventory = inventory(count: 40)
        let thetaGrid = (0...120).map { -6.0 + Double($0) * 0.1 }
        let storedPosterior = thetaGrid.map { theta in
            exp(-pow(theta - 0.5, 2) / (2 * 0.25 * 0.25))
        }
        let prior = VocabularyReaderPrior(
            languageCode: "en",
            thetaPosterior: storedPosterior,
            completedSessionCount: 3,
            verifiedEvidenceCount: 80,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_000),
            algorithmVersion: 3
        )

        func run(readerPrior: VocabularyReaderPrior?) throws -> (
            result: VocabularyAssessmentResult,
            validationCount: Int,
            requiredMinimum: Int,
            usedEligiblePrior: Bool
        ) {
            var assessment = AdaptiveVocabularyAssessment(
                inventory: inventory,
                mode: .targetCoverage(0.98),
                readerPrior: readerPrior,
                currentDate: Date(timeIntervalSince1970: 1_001)
            )
            while !assessment.isFinished {
                let question = try XCTUnwrap(assessment.nextQuestion())
                assessment.record(
                    question.difficulty < 0.5 ? .verifiedKnown : .reportedUnknown,
                    for: question.canonicalKey
                )
            }
            return (
                assessment.result(),
                assessment.answers.filter(\.wasValidation).count,
                assessment.requiredMinimumAnsweredQuestionCount,
                assessment.usedEligibleReaderPrior
            )
        }

        let cold = try run(readerPrior: nil)
        let warm = try run(readerPrior: prior)

        XCTAssertTrue(warm.usedEligiblePrior)
        XCTAssertGreaterThanOrEqual(warm.validationCount, 2)
        XCTAssertEqual(warm.requiredMinimum, 8)
        XCTAssertGreaterThanOrEqual(warm.result.diagnostics.conservativeCoverageLowerBound, 0.98)
        XCTAssertGreaterThanOrEqual(warm.result.answeredQuestionCount, 8)
        XCTAssertLessThanOrEqual(
            Double(warm.result.answeredQuestionCount),
            Double(cold.result.answeredQuestionCount) * 0.75
        )
    }

    func testIneligibleOrStalePriorRetainsTwentyQuestionMinimum() {
        let prior = VocabularyReaderPrior(
            languageCode: "en",
            thetaPosterior: Array(repeating: 1.0 / 121.0, count: 121),
            completedSessionCount: 2,
            verifiedEvidenceCount: 40,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_000),
            algorithmVersion: 3
        )
        let assessment = AdaptiveVocabularyAssessment(
            inventory: inventory(count: 40),
            mode: .allUnknown,
            readerPrior: prior,
            currentDate: Date(timeIntervalSince1970: 1_000 + 181 * 24 * 60 * 60)
        )

        XCTAssertFalse(assessment.usedEligibleReaderPrior)
        XCTAssertEqual(assessment.requiredMinimumAnsweredQuestionCount, 20)
    }

    func testReaderPriorFromAnotherLanguageIsNeverUsed() {
        let prior = VocabularyReaderPrior(
            languageCode: "de",
            thetaPosterior: Array(repeating: 1.0 / 121.0, count: 121),
            completedSessionCount: 3,
            verifiedEvidenceCount: 80,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_000),
            algorithmVersion: 3
        )
        let assessment = AdaptiveVocabularyAssessment(
            inventory: inventory(count: 40),
            mode: .targetCoverage(0.98),
            readerPrior: prior,
            currentDate: Date(timeIntervalSince1970: 1_001)
        )

        XCTAssertFalse(assessment.usedEligibleReaderPrior)
        XCTAssertEqual(assessment.requiredMinimumAnsweredQuestionCount, 20)
    }

    func testLemmaOnlyRestoredAnswerMigratesToLexicalCandidate() throws {
        let lexicalID = VocabularyLexicalItemID(language: "en", lemma: "book", partOfSpeech: .verb)
        let candidate = DocumentVocabularyCandidate(
            canonicalKey: lexicalID.canonicalKey,
            lemmaKey: "book",
            displayLemma: "book",
            lexicalItemID: lexicalID,
            partOfSpeech: .verb,
            observedForms: [VocabularyDocumentObservedForm(surface: "booked", occurrenceCount: 1)],
            occurrenceCount: 1,
            representativeRange: VocabularyDocumentSourceRange(unitIndex: 0, utf16Location: 0, utf16Length: 6),
            generalFrequencyRank: nil,
            difficulty: 0
        )
        let assessment = AdaptiveVocabularyAssessment(
            inventory: DocumentVocabularyInventory(languageCode: "en", candidates: [candidate]),
            mode: .allUnknown,
            restoredAnswers: [VocabularyAssessmentAnswer(canonicalKey: "book", evidence: .legacyKnown)]
        )

        XCTAssertEqual(assessment.answers.first?.canonicalKey, lexicalID.canonicalKey)
        XCTAssertGreaterThan(try XCTUnwrap(assessment.knownProbability(for: lexicalID.canonicalKey)), 0.5)
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
