import XCTest
import LeafReaderCore
@testable import LeafReaderValidation

final class VocabularyValidationBankXCTests: XCTestCase {
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
        let snapshot = try assessment.validationObservation()
        let bankA = try snapshot.evaluateValidationBank(VocabularyValidationBankConfiguration(
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
            .map { VocabularyValidationCoverageMassCount(knownOccurrenceMass: $0.key, sampleCount: $0.value.count) }
            .sorted { $0.knownOccurrenceMass < $1.knownOccurrenceMass }
        XCTAssertEqual(bankA.coverageMassHistogram, expectedHistogram)
    }

    func testB1RepeatsProductionThetaMassAndVariesOnlyIndependentLatentDraws() throws {
        let assessment = AdaptiveVocabularyAssessment(
            inventory: makeInventory(count: 20),
            mode: .targetCoverage(0.98)
        )
        let snapshot = try assessment.validationObservation()
        let bankA = try snapshot.evaluateValidationBank(configuration(.productionA, samples: 512, theta: 1, latent: 2))
        let sameSize = try snapshot.evaluateValidationBank(configuration(.independentLatentB1, samples: 512, theta: 3, latent: 4))
        let first = try snapshot.evaluateValidationBank(configuration(.independentLatentB1, samples: 1_024, theta: 3, latent: 4))
        let second = try snapshot.evaluateValidationBank(configuration(.independentLatentB1, samples: 1_024, theta: 999, latent: 5))

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
        let snapshot = try assessment.validationObservation()
        let original = try snapshot.evaluateValidationBank(configuration(.randomizedThetaAndLatentB2, samples: 512, theta: 41, latent: 42))
        let repeated = try snapshot.evaluateValidationBank(configuration(.randomizedThetaAndLatentB2, samples: 512, theta: 41, latent: 42))
        let changedTheta = try snapshot.evaluateValidationBank(configuration(.randomizedThetaAndLatentB2, samples: 512, theta: 43, latent: 42))
        let changedLatent = try snapshot.evaluateValidationBank(configuration(.randomizedThetaAndLatentB2, samples: 512, theta: 41, latent: 44))

        XCTAssertEqual(original, repeated)
        XCTAssertNotEqual(original.thetaPositionFingerprint, changedTheta.thetaPositionFingerprint)
        XCTAssertEqual(original.thetaPositionFingerprint, changedLatent.thetaPositionFingerprint)
        XCTAssertNotEqual(original.latentItemDrawFingerprint, changedLatent.latentItemDrawFingerprint)
    }

    func testB2InverseCDFSkipsZeroMassGridCells() throws {
        var posterior = Array(repeating: 0.0, count: 121)
        posterior[60] = 1
        let item = try XCTUnwrap(makeInventory(count: 1).candidates.first)
        let snapshot = try VocabularyAssessmentObservation(
            items: [VocabularyAssessmentObservation.Item(
                canonicalKey: item.canonicalKey,
                occurrenceCount: item.occurrenceCount,
                isIncluded: true,
                evidence: nil,
                responseCurve: Array(repeating: 0.5, count: 121),
                productionKnownMask: Array(repeating: 0, count: 8)
            )],
            posterior: posterior,
            epsilonKnowledge: 0.05,
            evidenceReliabilityScale: 1,
            coverageQuantile: 0.05,
            productionSelection: [],
            productionThetaIndexes: Array(repeating: 60, count: 512)
        )
        let result = try snapshot.evaluateValidationBank(configuration(
            .randomizedThetaAndLatentB2,
            samples: 512,
            theta: 0,
            latent: 1
        ))

        XCTAssertEqual(result.thetaPositionHistogram, [
            VocabularyValidationThetaPositionCount(thetaGridIndex: 60, sampleCount: 512)
        ])
    }

    func testSmallFixedBankMatchesHandEnumeratedMassesAndRejectsInvalidInputs() throws {
        let items = [
            VocabularyValidationFixedBankItem(
                canonicalKey: "a",
                occurrenceCount: 70,
                knownMaskWords: [0b0011]
            ),
            VocabularyValidationFixedBankItem(
                canonicalKey: "b",
                occurrenceCount: 30,
                knownMaskWords: [0b0101]
            )
        ]
        let result = try VocabularyValidationFixedBank.evaluate(
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
            VocabularyValidationCoverageMassCount(knownOccurrenceMass: 0, sampleCount: 1),
            VocabularyValidationCoverageMassCount(knownOccurrenceMass: 30, sampleCount: 1),
            VocabularyValidationCoverageMassCount(knownOccurrenceMass: 70, sampleCount: 1),
            VocabularyValidationCoverageMassCount(knownOccurrenceMass: 100, sampleCount: 1)
        ])

        let empty = try VocabularyValidationFixedBank.evaluate(
            items: [],
            sampleCount: 4,
            selectedKeys: [],
            coverageQuantile: 0.05,
            targetCoverage: 0.98
        )
        XCTAssertEqual(empty.coverageLowerBound, 1)
        XCTAssertEqual(empty.targetMissProbability, 0)

        XCTAssertThrowsError(try VocabularyValidationFixedBank.evaluate(
            items: items + [items[0]],
            sampleCount: 4,
            selectedKeys: [],
            coverageQuantile: 0.05,
            targetCoverage: 0.98
        )) { error in
            XCTAssertEqual(error as? VocabularyValidationBankError, .duplicateKey("a"))
        }
        XCTAssertThrowsError(try VocabularyValidationFixedBank.evaluate(
            items: [VocabularyValidationFixedBankItem(
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
            VocabularyValidationFixedBankItem(
                canonicalKey: "frequent",
                occurrenceCount: 80,
                knownMaskWords: [0b0011]
            ),
            VocabularyValidationFixedBankItem(
                canonicalKey: "rare",
                occurrenceCount: 20,
                knownMaskWords: [0b1100]
            )
        ]
        let optimistic = [
            VocabularyValidationFixedBankItem(
                canonicalKey: "frequent",
                occurrenceCount: 80,
                knownMaskWords: [0b1111]
            ),
            neutral[1]
        ]
        let neutralResult = try VocabularyValidationFixedBank.evaluate(
            items: neutral,
            sampleCount: 4,
            selectedKeys: [],
            coverageQuantile: 0.25,
            targetCoverage: 0.80
        )
        let optimisticResult = try VocabularyValidationFixedBank.evaluate(
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
        ).validationObservation()
        XCTAssertThrowsError(try snapshot.evaluateValidationBank(
            configuration(.independentLatentB1, samples: 576, theta: 1, latent: 2)
        )) { error in
            XCTAssertEqual(error as? VocabularyValidationBankError, .incompatibleB1SampleCount(576))
        }
    }

    func testInvalidWeightsMasksAndSelectionsAreRejected() throws {
        XCTAssertThrowsError(try VocabularyValidationFixedBank.evaluate(
            items: [VocabularyValidationFixedBankItem(
                canonicalKey: "bad-weight",
                occurrenceCount: 0,
                knownMaskWords: [0]
            )],
            sampleCount: 4,
            selectedKeys: [],
            coverageQuantile: 0.05,
            targetCoverage: 0.98
        ))
        XCTAssertThrowsError(try VocabularyValidationFixedBank.evaluate(
            items: [VocabularyValidationFixedBankItem(
                canonicalKey: "bad-mask",
                occurrenceCount: 1,
                knownMaskWords: []
            )],
            sampleCount: 4,
            selectedKeys: [],
            coverageQuantile: 0.05,
            targetCoverage: 0.98
        ))
        XCTAssertThrowsError(try VocabularyValidationFixedBank.evaluate(
            items: [VocabularyValidationFixedBankItem(
                canonicalKey: "known-key",
                occurrenceCount: 1,
                knownMaskWords: [0]
            )],
            sampleCount: 4,
            selectedKeys: ["missing-key"],
            coverageQuantile: 0.05,
            targetCoverage: 0.98
        ))

    }

    private func configuration(
        _ kind: VocabularyValidationBankKind,
        samples: Int,
        theta: UInt64,
        latent: UInt64
    ) -> VocabularyValidationBankConfiguration {
        VocabularyValidationBankConfiguration(
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
