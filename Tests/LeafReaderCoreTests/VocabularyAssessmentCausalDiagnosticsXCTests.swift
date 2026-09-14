import XCTest
import LeafReaderCore

final class VocabularyAssessmentCausalDiagnosticsXCTests: XCTestCase {
    func testProductionABankExactlyMatchesResultMasksAndCoverageQuantile() throws {
        let inventory = makeInventory(count: 12)
        var assessment = AdaptiveVocabularyAssessment(
            inventory: inventory,
            mode: .targetCoverage(0.90)
        )
        for index in 0..<8 {
            let question = try XCTUnwrap(assessment.nextQuestion())
            assessment.record(index.isMultiple(of: 3) ? .reportedUnknown : .verifiedKnown, for: question.id)
        }

        let result = assessment.result()
        let snapshot = try assessment.diagnosticSnapshot()
        let bankA = try snapshot.evaluate(VocabularyDiagnosticBankConfiguration(
            kind: .productionA,
            sampleCount: 512,
            thetaPositionSeed: 11,
            latentItemSeed: 12,
            targetCoverage: 0.90
        ))

        XCTAssertEqual(
            bankA.coverageLowerBound,
            result.diagnostics.conservativeCoverageLowerBound,
            accuracy: 1e-15
        )
        XCTAssertEqual(bankA.thetaPositionFingerprint, snapshot.productionThetaPositionFingerprint)
        XCTAssertEqual(bankA.latentItemDrawFingerprint, snapshot.productionLatentItemDrawFingerprint)

        let included = result.items.filter { $0.classification != .excluded }
        let selected = Set(included.filter(\.isSelected).map(\.id))
        let total = included.reduce(0) { $0 + $1.candidate.occurrenceCount }
        let totals = (0..<512).map { sample in
            included.reduce(0) { partial, item in
                if selected.contains(item.id) { return partial + item.candidate.occurrenceCount }
                let word = item.predictiveKnownMask[sample >> 6]
                let isKnown = word & (UInt64(1) << UInt64(sample & 63)) != 0
                return partial + (isKnown ? item.candidate.occurrenceCount : 0)
            }
        }
        let sorted = totals.sorted()
        let expectedIndex = Int((0.05 * Double(sorted.count - 1)).rounded(.down))
        XCTAssertEqual(bankA.coverageLowerBound, Double(sorted[expectedIndex]) / Double(total), accuracy: 1e-15)
        let expectedHistogram = Dictionary(grouping: totals, by: { $0 })
            .map { VocabularyDiagnosticCoverageMassCount(knownOccurrenceMass: $0.key, sampleCount: $0.value.count) }
            .sorted { $0.knownOccurrenceMass < $1.knownOccurrenceMass }
        XCTAssertEqual(bankA.coverageMassHistogram, expectedHistogram)
    }

    func testB1RepeatsProductionThetaMassAndVariesOnlyIndependentLatentDraws() throws {
        let assessment = AdaptiveVocabularyAssessment(
            inventory: makeInventory(count: 20),
            mode: .targetCoverage(0.98)
        )
        let snapshot = try assessment.diagnosticSnapshot()
        let bankA = try snapshot.evaluate(configuration(.productionA, samples: 512, theta: 1, latent: 2))
        let sameSize = try snapshot.evaluate(configuration(.independentLatentB1, samples: 512, theta: 3, latent: 4))
        let first = try snapshot.evaluate(configuration(.independentLatentB1, samples: 1_024, theta: 3, latent: 4))
        let second = try snapshot.evaluate(configuration(.independentLatentB1, samples: 1_024, theta: 999, latent: 5))

        XCTAssertEqual(sameSize.thetaPositionFingerprint, bankA.thetaPositionFingerprint)
        let productionMass = Dictionary(uniqueKeysWithValues: bankA.thetaPositionHistogram.map {
            ($0.thetaGridIndex, $0.sampleCount)
        })
        for position in first.thetaPositionHistogram {
            XCTAssertEqual(position.sampleCount, 2 * (productionMass[position.thetaGridIndex] ?? 0))
        }
        XCTAssertEqual(first.thetaPositionFingerprint, second.thetaPositionFingerprint)
        XCTAssertNotEqual(first.latentItemDrawFingerprint, second.latentItemDrawFingerprint)
    }

    func testB2SeparatesThetaJitterAndLatentSeedsReproducibly() throws {
        let assessment = AdaptiveVocabularyAssessment(
            inventory: makeInventory(count: 20),
            mode: .targetCoverage(0.98)
        )
        let snapshot = try assessment.diagnosticSnapshot()
        let original = try snapshot.evaluate(configuration(.randomizedThetaAndLatentB2, samples: 512, theta: 41, latent: 42))
        let repeated = try snapshot.evaluate(configuration(.randomizedThetaAndLatentB2, samples: 512, theta: 41, latent: 42))
        let changedTheta = try snapshot.evaluate(configuration(.randomizedThetaAndLatentB2, samples: 512, theta: 43, latent: 42))
        let changedLatent = try snapshot.evaluate(configuration(.randomizedThetaAndLatentB2, samples: 512, theta: 41, latent: 44))

        XCTAssertEqual(original, repeated)
        XCTAssertNotEqual(original.thetaPositionFingerprint, changedTheta.thetaPositionFingerprint)
        XCTAssertEqual(original.thetaPositionFingerprint, changedLatent.thetaPositionFingerprint)
        XCTAssertNotEqual(original.latentItemDrawFingerprint, changedLatent.latentItemDrawFingerprint)
    }

    func testB2InverseCDFSkipsZeroMassGridCells() throws {
        var posterior = Array(repeating: 0.0, count: 121)
        posterior[60] = 1
        let item = try XCTUnwrap(makeInventory(count: 1).candidates.first)
        let snapshot = try VocabularyAssessmentDiagnosticSnapshot(
            items: [VocabularyAssessmentDiagnosticSnapshot.Item(
                candidate: item,
                evidence: nil,
                responseCurve: Array(repeating: 0.5, count: 121),
                productionKnownMask: Array(repeating: 0, count: 8),
                isIncluded: true
            )],
            posterior: posterior,
            epsilonKnowledge: 0.05,
            evidenceReliabilityScale: 1,
            coverageQuantile: 0.05,
            productionSelection: [],
            productionThetaIndexes: Array(repeating: 60, count: 512)
        )
        let result = try snapshot.evaluate(configuration(
            .randomizedThetaAndLatentB2,
            samples: 512,
            theta: 0,
            latent: 1
        ))

        XCTAssertEqual(result.thetaPositionHistogram, [
            VocabularyDiagnosticThetaPositionCount(thetaGridIndex: 60, sampleCount: 512)
        ])
    }

    func testObservationSnapshotDoesNotChangeResultOrFutureQuestionPath() throws {
        let inventory = makeInventory(count: 40)
        var observed = AdaptiveVocabularyAssessment(inventory: inventory, mode: .targetCoverage(0.98))
        var control = observed
        for index in 0..<12 {
            let observedQuestion = try XCTUnwrap(observed.nextQuestion())
            let controlQuestion = try XCTUnwrap(control.nextQuestion())
            XCTAssertEqual(observedQuestion.id, controlQuestion.id)
            let evidence: VocabularyKnowledgeEvidence = index.isMultiple(of: 2) ? .verifiedKnown : .reportedUnknown
            observed.record(evidence, for: observedQuestion.id)
            control.record(evidence, for: controlQuestion.id)
        }

        let before = observed.result()
        let snapshot = try observed.diagnosticSnapshot()
        _ = try snapshot.evaluate(configuration(
            .independentLatentB1,
            samples: 512,
            theta: 100,
            latent: 101
        ))
        let after = observed.result()
        XCTAssertEqual(before, after)
        while !observed.isFinished, !control.isFinished {
            let observedQuestion = try XCTUnwrap(observed.nextQuestion())
            let controlQuestion = try XCTUnwrap(control.nextQuestion())
            XCTAssertEqual(observedQuestion.id, controlQuestion.id)
            let evidence: VocabularyKnowledgeEvidence = observed.answeredQuestionCount.isMultiple(of: 2)
                ? .verifiedKnown
                : .reportedUnknown
            observed.record(evidence, for: observedQuestion.id)
            control.record(evidence, for: controlQuestion.id)
        }
        XCTAssertEqual(observed.isFinished, control.isFinished)
        XCTAssertEqual(observed.answers, control.answers)
        XCTAssertEqual(observed.thetaPosteriorSnapshot, control.thetaPosteriorSnapshot)
        XCTAssertEqual(observed.result(), control.result())
    }

    func testDiagnosticContinuationLogsNaturalStopButKeepsHardCeilingAndUniqueness() throws {
        var assessment = AdaptiveVocabularyAssessment(
            inventory: makeInventory(count: 100),
            mode: .allUnknown
        )
        while !assessment.isFinished {
            let question = try XCTUnwrap(assessment.nextQuestion())
            assessment.record(.verifiedKnown, for: question.id)
        }
        XCTAssertEqual(assessment.diagnosticNaturalStopReason, .lowExpectedValue)
        let naturalCount = assessment.answeredQuestionCount
        XCTAssertLessThan(naturalCount, 80)

        while let question = assessment.nextQuestionForDiagnosticContinuation() {
            assessment.record(.verifiedKnown, for: question.id)
        }
        XCTAssertEqual(assessment.answeredQuestionCount, 80)
        XCTAssertEqual(Set(assessment.answers.map(\.canonicalKey)).count, assessment.answers.count)
        XCTAssertNil(assessment.nextQuestionForDiagnosticContinuation())
    }

    func testRestoredCommonEvidencePathPreservesMetadataAndPosterior() throws {
        let inventory = makeInventory(count: 40)
        var source = AdaptiveVocabularyAssessment(inventory: inventory, mode: .allUnknown)
        for index in 0..<20 {
            let question = try XCTUnwrap(source.nextQuestion())
            source.record(index.isMultiple(of: 4) ? .reportedUnknown : .verifiedKnown, for: question.id)
        }
        let replay = AdaptiveVocabularyAssessment(
            inventory: inventory,
            mode: .allUnknown,
            restoredAnswers: source.answers
        )

        XCTAssertEqual(replay.answers, source.answers)
        XCTAssertEqual(replay.thetaPosteriorSnapshot, source.thetaPosteriorSnapshot)
        XCTAssertEqual(replay.result(), source.result())
    }

    func testSmallFixedBankMatchesHandEnumeratedMassesAndRejectsInvalidInputs() throws {
        let items = [
            VocabularyDiagnosticFixedBankItem(
                canonicalKey: "a",
                occurrenceCount: 70,
                knownMaskWords: [0b0011]
            ),
            VocabularyDiagnosticFixedBankItem(
                canonicalKey: "b",
                occurrenceCount: 30,
                knownMaskWords: [0b0101]
            )
        ]
        let result = try VocabularyDiagnosticFixedBank.evaluate(
            items: items,
            sampleCount: 4,
            selectedKeys: [],
            coverageQuantile: 0.25,
            targetCoverage: 0.80
        )

        XCTAssertEqual(result.totalOccurrences, 100)
        XCTAssertEqual(result.coverageLowerBound, 0)
        XCTAssertEqual(result.targetMissProbability, 0.75)
        XCTAssertEqual(result.coverageMassHistogram, [
            VocabularyDiagnosticCoverageMassCount(knownOccurrenceMass: 0, sampleCount: 1),
            VocabularyDiagnosticCoverageMassCount(knownOccurrenceMass: 30, sampleCount: 1),
            VocabularyDiagnosticCoverageMassCount(knownOccurrenceMass: 70, sampleCount: 1),
            VocabularyDiagnosticCoverageMassCount(knownOccurrenceMass: 100, sampleCount: 1)
        ])

        let empty = try VocabularyDiagnosticFixedBank.evaluate(
            items: [],
            sampleCount: 4,
            selectedKeys: [],
            coverageQuantile: 0.05,
            targetCoverage: 0.98
        )
        XCTAssertEqual(empty.coverageLowerBound, 1)
        XCTAssertEqual(empty.targetMissProbability, 0)

        XCTAssertThrowsError(try VocabularyDiagnosticFixedBank.evaluate(
            items: items + [items[0]],
            sampleCount: 4,
            selectedKeys: [],
            coverageQuantile: 0.05,
            targetCoverage: 0.98
        )) { error in
            XCTAssertEqual(error as? VocabularyDiagnosticInputError, .duplicateKey("a"))
        }
        XCTAssertThrowsError(try VocabularyDiagnosticFixedBank.evaluate(
            items: [VocabularyDiagnosticFixedBankItem(
                canonicalKey: "excluded",
                occurrenceCount: 1,
                isIncluded: false,
                knownMaskWords: [0]
            )],
            sampleCount: 4,
            selectedKeys: ["excluded"],
            coverageQuantile: 0.05,
            targetCoverage: 0.98
        ))
    }

    func testFixedDeckControlExposesDeliberatelyOptimisticBank() throws {
        let neutral = [
            VocabularyDiagnosticFixedBankItem(
                canonicalKey: "frequent",
                occurrenceCount: 80,
                knownMaskWords: [0b0011]
            ),
            VocabularyDiagnosticFixedBankItem(
                canonicalKey: "rare",
                occurrenceCount: 20,
                knownMaskWords: [0b1100]
            )
        ]
        let optimistic = [
            VocabularyDiagnosticFixedBankItem(
                canonicalKey: "frequent",
                occurrenceCount: 80,
                knownMaskWords: [0b1111]
            ),
            neutral[1]
        ]
        let neutralResult = try VocabularyDiagnosticFixedBank.evaluate(
            items: neutral,
            sampleCount: 4,
            selectedKeys: [],
            coverageQuantile: 0.25,
            targetCoverage: 0.80
        )
        let optimisticResult = try VocabularyDiagnosticFixedBank.evaluate(
            items: optimistic,
            sampleCount: 4,
            selectedKeys: [],
            coverageQuantile: 0.25,
            targetCoverage: 0.80
        )

        XCTAssertEqual(neutralResult.coverageLowerBound, 0.20)
        XCTAssertEqual(optimisticResult.coverageLowerBound, 0.80)
        XCTAssertGreaterThan(optimisticResult.coverageLowerBound, neutralResult.coverageLowerBound)
    }

    func testB1RejectsCountsThatCannotPreserveProductionThetaMass() throws {
        let snapshot = try AdaptiveVocabularyAssessment(
            inventory: makeInventory(count: 20),
            mode: .targetCoverage(0.98)
        ).diagnosticSnapshot()
        XCTAssertThrowsError(try snapshot.evaluate(
            configuration(.independentLatentB1, samples: 576, theta: 1, latent: 2)
        )) { error in
            XCTAssertEqual(error as? VocabularyDiagnosticInputError, .incompatibleB1SampleCount(576))
        }
    }

    func testInvalidWeightsMasksSelectionsPosteriorsAndProbabilitiesAreRejected() throws {
        XCTAssertThrowsError(try VocabularyDiagnosticFixedBank.evaluate(
            items: [VocabularyDiagnosticFixedBankItem(
                canonicalKey: "bad-weight",
                occurrenceCount: 0,
                knownMaskWords: [0]
            )],
            sampleCount: 4,
            selectedKeys: [],
            coverageQuantile: 0.05,
            targetCoverage: 0.98
        ))
        XCTAssertThrowsError(try VocabularyDiagnosticFixedBank.evaluate(
            items: [VocabularyDiagnosticFixedBankItem(
                canonicalKey: "bad-mask",
                occurrenceCount: 1,
                knownMaskWords: []
            )],
            sampleCount: 4,
            selectedKeys: [],
            coverageQuantile: 0.05,
            targetCoverage: 0.98
        ))
        XCTAssertThrowsError(try VocabularyDiagnosticFixedBank.evaluate(
            items: [VocabularyDiagnosticFixedBankItem(
                canonicalKey: "known-key",
                occurrenceCount: 1,
                knownMaskWords: [0]
            )],
            sampleCount: 4,
            selectedKeys: ["missing-key"],
            coverageQuantile: 0.05,
            targetCoverage: 0.98
        ))

        let candidate = try XCTUnwrap(makeInventory(count: 1).candidates.first)
        let validItem = VocabularyAssessmentDiagnosticSnapshot.Item(
            candidate: candidate,
            evidence: nil,
            responseCurve: Array(repeating: 0.5, count: 121),
            productionKnownMask: Array(repeating: 0, count: 8),
            isIncluded: true
        )
        XCTAssertThrowsError(try VocabularyAssessmentDiagnosticSnapshot(
            items: [validItem],
            posterior: Array(repeating: 0, count: 121),
            epsilonKnowledge: 0.05,
            evidenceReliabilityScale: 1,
            coverageQuantile: 0.05,
            productionSelection: [],
            productionThetaIndexes: Array(repeating: 60, count: 512)
        ))
        XCTAssertThrowsError(try VocabularyAssessmentDiagnosticSnapshot(
            items: [VocabularyAssessmentDiagnosticSnapshot.Item(
                candidate: candidate,
                evidence: nil,
                responseCurve: [Double.nan] + Array(repeating: 0.5, count: 120),
                productionKnownMask: Array(repeating: 0, count: 8),
                isIncluded: true
            )],
            posterior: Array(repeating: 1.0 / 121.0, count: 121),
            epsilonKnowledge: 0.05,
            evidenceReliabilityScale: 1,
            coverageQuantile: 0.05,
            productionSelection: [],
            productionThetaIndexes: Array(repeating: 60, count: 512)
        ))
    }

    private func configuration(
        _ kind: VocabularyDiagnosticBankKind,
        samples: Int,
        theta: UInt64,
        latent: UInt64
    ) -> VocabularyDiagnosticBankConfiguration {
        VocabularyDiagnosticBankConfiguration(
            kind: kind,
            sampleCount: samples,
            thetaPositionSeed: theta,
            latentItemSeed: latent,
            targetCoverage: 0.98
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
                        unitIndex: 0,
                        utf16Location: index,
                        utf16Length: key.utf16.count
                    ),
                    generalFrequencyRank: nil,
                    difficulty: -3 + 6 * Double(index) / Double(max(1, count - 1))
                )
            }
        )
    }
}
