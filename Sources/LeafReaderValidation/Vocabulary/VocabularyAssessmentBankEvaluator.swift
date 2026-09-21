import Foundation
import LeafReaderCore

package enum VocabularyValidationBankKind: String, Codable, Equatable, Sendable {
    case productionA
    case independentLatentB1
    case randomizedThetaAndLatentB2
}

package enum VocabularyValidationBankError: Error, Equatable, Sendable {
    case invalidSampleCount(Int)
    case incompatibleB1SampleCount(Int)
    case invalidCoverageQuantile(Double)
    case invalidTargetCoverage(Double)
    case invalidOccurrenceCount(key: String, count: Int)
    case duplicateKey(String)
    case invalidMaskShape(key: String, expected: Int, actual: Int)
    case unknownSelectionKey(String)
    case excludedSelectionKey(String)
}

package struct VocabularyValidationCoverageMassCount: Codable, Equatable, Sendable {
    package let knownOccurrenceMass: Int
    package let sampleCount: Int

    package init(knownOccurrenceMass: Int, sampleCount: Int) {
        self.knownOccurrenceMass = knownOccurrenceMass
        self.sampleCount = sampleCount
    }
}

package struct VocabularyValidationFixedBankItem: Equatable, Sendable {
    package let canonicalKey: String
    package let occurrenceCount: Int
    package let isIncluded: Bool
    package let knownMaskWords: [UInt64]

    package init(
        canonicalKey: String,
        occurrenceCount: Int,
        isIncluded: Bool = true,
        knownMaskWords: [UInt64]
    ) {
        self.canonicalKey = canonicalKey
        self.occurrenceCount = occurrenceCount
        self.isIncluded = isIncluded
        self.knownMaskWords = knownMaskWords
    }
}

package struct VocabularyValidationFixedBankResult: Codable, Equatable, Sendable {
    package let sampleCount: Int
    package let totalOccurrences: Int
    package let coverageQuantile: Double
    package let coverageLowerBound: Double
    package let targetCoverage: Double
    package let targetMissProbability: Double
    package let coverageMassHistogram: [VocabularyValidationCoverageMassCount]
}

package enum VocabularyValidationFixedBank {
    package static func evaluate(
        items: [VocabularyValidationFixedBankItem],
        sampleCount: Int,
        selectedKeys: Set<String>,
        coverageQuantile: Double,
        targetCoverage: Double
    ) throws -> VocabularyValidationFixedBankResult {
        guard sampleCount > 0 else {
            throw VocabularyValidationBankError.invalidSampleCount(sampleCount)
        }
        guard coverageQuantile.isFinite, (0...0.5).contains(coverageQuantile) else {
            throw VocabularyValidationBankError.invalidCoverageQuantile(coverageQuantile)
        }
        guard targetCoverage.isFinite, (0...1).contains(targetCoverage) else {
            throw VocabularyValidationBankError.invalidTargetCoverage(targetCoverage)
        }

        let maskWordCount = (sampleCount + 63) / 64
        var seen = Set<String>()
        var includedKeys = Set<String>()
        var excludedKeys = Set<String>()
        var totalOccurrences = 0
        for item in items {
            guard seen.insert(item.canonicalKey).inserted else {
                throw VocabularyValidationBankError.duplicateKey(item.canonicalKey)
            }
            guard item.occurrenceCount > 0 else {
                throw VocabularyValidationBankError.invalidOccurrenceCount(
                    key: item.canonicalKey,
                    count: item.occurrenceCount
                )
            }
            guard item.knownMaskWords.count == maskWordCount else {
                throw VocabularyValidationBankError.invalidMaskShape(
                    key: item.canonicalKey,
                    expected: maskWordCount,
                    actual: item.knownMaskWords.count
                )
            }
            if item.isIncluded {
                includedKeys.insert(item.canonicalKey)
                let (next, overflow) = totalOccurrences.addingReportingOverflow(item.occurrenceCount)
                guard !overflow else {
                    throw VocabularyValidationBankError.invalidOccurrenceCount(
                        key: item.canonicalKey,
                        count: item.occurrenceCount
                    )
                }
                totalOccurrences = next
            } else {
                excludedKeys.insert(item.canonicalKey)
            }
        }
        for key in selectedKeys {
            if excludedKeys.contains(key) {
                throw VocabularyValidationBankError.excludedSelectionKey(key)
            }
            guard includedKeys.contains(key) else {
                throw VocabularyValidationBankError.unknownSelectionKey(key)
            }
        }

        var totals = Array(repeating: 0, count: sampleCount)
        for item in items where item.isIncluded {
            if selectedKeys.contains(item.canonicalKey) {
                for sampleIndex in totals.indices {
                    totals[sampleIndex] += item.occurrenceCount
                }
                continue
            }
            for sampleIndex in totals.indices where maskContains(item.knownMaskWords, sampleIndex) {
                totals[sampleIndex] += item.occurrenceCount
            }
        }

        let lowerBound: Double
        let missProbability: Double
        if totalOccurrences == 0 {
            lowerBound = 1
            missProbability = 0
        } else {
            let sorted = totals.sorted()
            let quantileIndex = Int(
                (coverageQuantile * Double(sorted.count - 1)).rounded(.down)
            )
            lowerBound = Double(sorted[quantileIndex]) / Double(totalOccurrences)
            missProbability = Double(totals.lazy.filter {
                Double($0) / Double(totalOccurrences) < targetCoverage
            }.count) / Double(sampleCount)
        }
        let histogram = Dictionary(grouping: totals, by: { $0 })
            .map { VocabularyValidationCoverageMassCount(knownOccurrenceMass: $0.key, sampleCount: $0.value.count) }
            .sorted { $0.knownOccurrenceMass < $1.knownOccurrenceMass }
        return VocabularyValidationFixedBankResult(
            sampleCount: sampleCount,
            totalOccurrences: totalOccurrences,
            coverageQuantile: coverageQuantile,
            coverageLowerBound: lowerBound,
            targetCoverage: targetCoverage,
            targetMissProbability: missProbability,
            coverageMassHistogram: histogram
        )
    }

    private static func maskContains(_ mask: [UInt64], _ sampleIndex: Int) -> Bool {
        mask[sampleIndex >> 6] & (UInt64(1) << UInt64(sampleIndex & 63)) != 0
    }
}

package struct VocabularyValidationBankConfiguration: Codable, Equatable, Sendable {
    package let kind: VocabularyValidationBankKind
    package let sampleCount: Int
    package let thetaPositionSeed: UInt64
    package let latentItemSeed: UInt64
    package let targetCoverage: Double

    package init(
        kind: VocabularyValidationBankKind,
        sampleCount: Int,
        thetaPositionSeed: UInt64,
        latentItemSeed: UInt64,
        targetCoverage: Double
    ) {
        self.kind = kind
        self.sampleCount = sampleCount
        self.thetaPositionSeed = thetaPositionSeed
        self.latentItemSeed = latentItemSeed
        self.targetCoverage = targetCoverage
    }
}

package struct VocabularyValidationBankResult: Codable, Equatable, Sendable {
    package let kind: VocabularyValidationBankKind
    package let sampleCount: Int
    package let coverageLowerBound: Double
    package let targetMissProbability: Double
    package let thetaPositionFingerprint: String
    package let latentItemDrawFingerprint: String
    package let uniqueThetaPositionCount: Int
    package let thetaPositionHistogram: [VocabularyValidationThetaPositionCount]
    package let coverageMassHistogram: [VocabularyValidationCoverageMassCount]
}

package struct VocabularyValidationThetaPositionCount: Codable, Equatable, Sendable {
    package let thetaGridIndex: Int
    package let sampleCount: Int

    package init(thetaGridIndex: Int, sampleCount: Int) {
        self.thetaGridIndex = thetaGridIndex
        self.sampleCount = sampleCount
    }
}

extension VocabularyAssessmentObservation {
    package func evaluateValidationBank(
        _ configuration: VocabularyValidationBankConfiguration,
        selectedKeys: Set<String>? = nil
    ) throws -> VocabularyValidationBankResult {
        let selection = selectedKeys ?? productionSelection
        let thetaIndexes: [Int]
        let masks: [[UInt64]]
        let thetaFingerprint: String
        let latentFingerprint: String

        switch configuration.kind {
        case .productionA:
            guard configuration.sampleCount == AdaptiveVocabularyAssessment.predictiveSampleCount else {
                throw VocabularyValidationBankError.invalidSampleCount(configuration.sampleCount)
            }
            thetaIndexes = productionThetaIndexes
            masks = items.map(\.productionKnownMask)
            thetaFingerprint = productionThetaPositionFingerprint
            latentFingerprint = productionLatentItemDrawFingerprint
        case .independentLatentB1:
            guard configuration.sampleCount > 0,
                  configuration.sampleCount.isMultiple(of: 64) else {
                throw VocabularyValidationBankError.invalidSampleCount(configuration.sampleCount)
            }
            guard configuration.sampleCount.isMultiple(
                of: AdaptiveVocabularyAssessment.predictiveSampleCount
            ) else {
                throw VocabularyValidationBankError.incompatibleB1SampleCount(configuration.sampleCount)
            }
            let repetitions = configuration.sampleCount / AdaptiveVocabularyAssessment.predictiveSampleCount
            thetaIndexes = productionThetaIndexes.flatMap { index in
                Array(repeating: index, count: repetitions)
            }
            let generated = generatedMasks(
                thetaIndexes: thetaIndexes,
                latentSeed: configuration.latentItemSeed
            )
            masks = generated.masks
            thetaFingerprint = Self.fingerprint(integers: thetaIndexes)
            latentFingerprint = generated.fingerprint
        case .randomizedThetaAndLatentB2:
            guard configuration.sampleCount > 0,
                  configuration.sampleCount.isMultiple(of: 64) else {
                throw VocabularyValidationBankError.invalidSampleCount(configuration.sampleCount)
            }
            thetaIndexes = randomizedStratifiedThetaIndexes(
                sampleCount: configuration.sampleCount,
                seed: configuration.thetaPositionSeed
            )
            let generated = generatedMasks(
                thetaIndexes: thetaIndexes,
                latentSeed: configuration.latentItemSeed
            )
            masks = generated.masks
            thetaFingerprint = Self.fingerprint(integers: thetaIndexes)
            latentFingerprint = generated.fingerprint
        }

        let bankItems = zip(items, masks).map { item, mask in
            VocabularyValidationFixedBankItem(
                canonicalKey: item.canonicalKey,
                occurrenceCount: item.occurrenceCount,
                isIncluded: item.isIncluded,
                knownMaskWords: mask
            )
        }
        let fixedResult = try VocabularyValidationFixedBank.evaluate(
            items: bankItems,
            sampleCount: configuration.sampleCount,
            selectedKeys: selection,
            coverageQuantile: coverageQuantile,
            targetCoverage: configuration.targetCoverage
        )
        return VocabularyValidationBankResult(
            kind: configuration.kind,
            sampleCount: configuration.sampleCount,
            coverageLowerBound: fixedResult.coverageLowerBound,
            targetMissProbability: fixedResult.targetMissProbability,
            thetaPositionFingerprint: thetaFingerprint,
            latentItemDrawFingerprint: latentFingerprint,
            uniqueThetaPositionCount: Set(thetaIndexes).count,
            thetaPositionHistogram: Dictionary(grouping: thetaIndexes, by: { $0 })
                .map {
                    VocabularyValidationThetaPositionCount(
                        thetaGridIndex: $0.key,
                        sampleCount: $0.value.count
                    )
                }
                .sorted { $0.thetaGridIndex < $1.thetaGridIndex },
            coverageMassHistogram: fixedResult.coverageMassHistogram
        )
    }

    private func generatedMasks(
        thetaIndexes: [Int],
        latentSeed: UInt64
    ) -> (masks: [[UInt64]], fingerprint: String) {
        let maskWordCount = thetaIndexes.count / 64
        var state = latentSeed == 0 ? 0xA076_1D64_78BD_642F : latentSeed
        var fingerprint = VocabularyValidationFingerprint()
        var masks: [[UInt64]] = []
        masks.reserveCapacity(items.count)
        for item in items {
            var mask = Array(repeating: UInt64(0), count: maskWordCount)
            guard item.isIncluded else {
                masks.append(mask)
                continue
            }
            for sampleIndex in thetaIndexes.indices {
                let baseKnown = item.responseCurve[thetaIndexes[sampleIndex]]
                let latentKnown = VocabularyKnowledgeModel.adjustedKnownProbability(
                    baseKnownProbability: baseKnown,
                    epsilonKnowledge: epsilonKnowledge
                )
                let knownProbability = item.evidence.map {
                    VocabularyObservationModel.posteriorKnownProbability(
                        prior: latentKnown,
                        evidence: $0,
                        reliabilityScale: evidenceReliabilityScale
                    )
                } ?? latentKnown
                let draw = Self.nextRandomUnit(state: &state)
                fingerprint.mix(draw.bitPattern)
                if draw < knownProbability {
                    mask[sampleIndex >> 6] |= UInt64(1) << UInt64(sampleIndex & 63)
                }
            }
            masks.append(mask)
        }
        return (masks, fingerprint.hex)
    }

    /// B2 uses independent jitter inside each of `sampleCount` equal posterior
    /// mass strata. Zero-mass grid cells are skipped by inverse-CDF lookup and
    /// the final grid cell owns any floating-point remainder at the upper edge.
    private func randomizedStratifiedThetaIndexes(sampleCount: Int, seed: UInt64) -> [Int] {
        var state = seed == 0 ? 0xE703_7ED1_A0B4_28DB : seed
        var cumulative: [Double] = []
        cumulative.reserveCapacity(posterior.count)
        var running = 0.0
        for weight in posterior {
            running += weight
            cumulative.append(running)
        }
        return (0..<sampleCount).map { sampleIndex in
            let jitter = Self.nextRandomUnit(state: &state)
            let quantile = (Double(sampleIndex) + jitter) / Double(sampleCount)
            var lower = 0
            var upper = cumulative.count - 1
            while lower < upper {
                let middle = (lower + upper) >> 1
                if cumulative[middle] <= quantile {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
            return lower
        }
    }

    private static func nextRandomUnit(state: inout UInt64) -> Double {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let value = state &* 0x2545_F491_4F6C_DD1D
        return Double(value >> 11) * 0x1.0p-53
    }

    private static func fingerprint(integers: [Int]) -> String {
        var fingerprint = VocabularyValidationFingerprint()
        for integer in integers { fingerprint.mix(UInt64(integer)) }
        return fingerprint.hex
    }

    private static func fingerprint(words: [UInt64]) -> String {
        var fingerprint = VocabularyValidationFingerprint()
        for word in words { fingerprint.mix(word) }
        return fingerprint.hex
    }

}

private struct VocabularyValidationFingerprint {
    private var value: UInt64 = 0xCBF2_9CE4_8422_2325

    mutating func mix(_ byte: UInt8) {
        value ^= UInt64(byte)
        value &*= 0x0000_0100_0000_01B3
    }

    mutating func mix(_ integer: UInt64) {
        withUnsafeBytes(of: integer.littleEndian) { bytes in
            for byte in bytes { mix(byte) }
        }
    }

    mutating func mix(_ string: String) {
        for byte in string.utf8 { mix(byte) }
    }

    var hex: String { String(format: "%016llx", value) }
}
