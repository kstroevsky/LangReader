import Foundation

package enum VocabularyAssessmentObservationError: Error, Equatable, Sendable {
    case invalidSampleCount(Int)
    case invalidCoverageQuantile(Double)
    case invalidOccurrenceCount(key: String, count: Int)
    case invalidProbability(key: String)
    case invalidPosterior
    case duplicateKey(String)
    case invalidMaskShape(key: String, expected: Int, actual: Int)
    case unknownSelectionKey(String)
    case excludedSelectionKey(String)
}

/// An immutable account of the actual production assessment state.
/// Experimental banks and counterfactual selections are interpreted outside Core.
package struct VocabularyAssessmentObservation: Sendable {
    package struct Item: Sendable {
        package let canonicalKey: String
        package let occurrenceCount: Int
        package let isIncluded: Bool
        package let evidence: VocabularyKnowledgeEvidence?
        package let responseCurve: [Double]
        package let productionKnownMask: [UInt64]

        package init(
            canonicalKey: String,
            occurrenceCount: Int,
            isIncluded: Bool,
            evidence: VocabularyKnowledgeEvidence?,
            responseCurve: [Double],
            productionKnownMask: [UInt64]
        ) {
            self.canonicalKey = canonicalKey
            self.occurrenceCount = occurrenceCount
            self.isIncluded = isIncluded
            self.evidence = evidence
            self.responseCurve = responseCurve
            self.productionKnownMask = productionKnownMask
        }
    }

    package let items: [Item]
    package let posterior: [Double]
    package let epsilonKnowledge: Double
    package let evidenceReliabilityScale: Double
    package let coverageQuantile: Double
    package let productionSelection: Set<String>
    package let productionThetaIndexes: [Int]
    package let totalOccurrences: Int
    package let sourceFingerprint: String
    package let productionThetaPositionFingerprint: String
    package let productionLatentItemDrawFingerprint: String

    package init(
        items: [Item],
        posterior: [Double],
        epsilonKnowledge: Double,
        evidenceReliabilityScale: Double,
        coverageQuantile: Double,
        productionSelection: Set<String>,
        productionThetaIndexes: [Int]
    ) throws {
        guard posterior.count == 121,
              posterior.allSatisfy({ $0.isFinite && $0 >= 0 }),
              posterior.reduce(0, +).isFinite,
              posterior.reduce(0, +) > 0 else {
            throw VocabularyAssessmentObservationError.invalidPosterior
        }
        guard coverageQuantile.isFinite, (0...0.5).contains(coverageQuantile) else {
            throw VocabularyAssessmentObservationError.invalidCoverageQuantile(coverageQuantile)
        }
        guard productionThetaIndexes.count == AdaptiveVocabularyAssessment.predictiveSampleCount else {
            throw VocabularyAssessmentObservationError.invalidSampleCount(productionThetaIndexes.count)
        }

        var seen = Set<String>()
        var includedKeys = Set<String>()
        var excludedKeys = Set<String>()
        var denominator = 0
        for item in items {
            let key = item.canonicalKey
            guard seen.insert(key).inserted else {
                throw VocabularyAssessmentObservationError.duplicateKey(key)
            }
            guard item.occurrenceCount > 0 else {
                throw VocabularyAssessmentObservationError.invalidOccurrenceCount(
                    key: key, count: item.occurrenceCount
                )
            }
            guard item.responseCurve.count == posterior.count,
                  item.responseCurve.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
                throw VocabularyAssessmentObservationError.invalidProbability(key: key)
            }
            guard item.productionKnownMask.count == AdaptiveVocabularyAssessment.predictiveSampleCount / 64 else {
                throw VocabularyAssessmentObservationError.invalidMaskShape(
                    key: key,
                    expected: AdaptiveVocabularyAssessment.predictiveSampleCount / 64,
                    actual: item.productionKnownMask.count
                )
            }
            if item.isIncluded {
                includedKeys.insert(key)
                let (next, overflow) = denominator.addingReportingOverflow(item.occurrenceCount)
                guard !overflow else {
                    throw VocabularyAssessmentObservationError.invalidOccurrenceCount(
                        key: key, count: item.occurrenceCount
                    )
                }
                denominator = next
            } else {
                excludedKeys.insert(key)
            }
        }
        for key in productionSelection {
            if excludedKeys.contains(key) {
                throw VocabularyAssessmentObservationError.excludedSelectionKey(key)
            }
            guard includedKeys.contains(key) else {
                throw VocabularyAssessmentObservationError.unknownSelectionKey(key)
            }
        }

        self.items = items
        self.posterior = posterior
        self.epsilonKnowledge = epsilonKnowledge
        self.evidenceReliabilityScale = evidenceReliabilityScale
        self.coverageQuantile = coverageQuantile
        self.productionSelection = productionSelection
        self.productionThetaIndexes = productionThetaIndexes
        totalOccurrences = denominator
        sourceFingerprint = Self.snapshotFingerprint(
            items: items,
            posterior: posterior,
            epsilonKnowledge: epsilonKnowledge,
            evidenceReliabilityScale: evidenceReliabilityScale,
            selection: productionSelection
        )
        productionThetaPositionFingerprint = Self.fingerprint(integers: productionThetaIndexes)
        productionLatentItemDrawFingerprint = Self.fingerprint(words: items.flatMap(\.productionKnownMask))
    }

    private static func fingerprint(integers: [Int]) -> String {
        var fingerprint = ObservationFingerprint()
        for integer in integers { fingerprint.mix(UInt64(integer)) }
        return fingerprint.hex
    }

    private static func fingerprint(words: [UInt64]) -> String {
        var fingerprint = ObservationFingerprint()
        for word in words { fingerprint.mix(word) }
        return fingerprint.hex
    }

    private static func snapshotFingerprint(
        items: [Item],
        posterior: [Double],
        epsilonKnowledge: Double,
        evidenceReliabilityScale: Double,
        selection: Set<String>
    ) -> String {
        var fingerprint = ObservationFingerprint()
        for item in items {
            fingerprint.mix(item.canonicalKey)
            fingerprint.mix(UInt64(item.occurrenceCount))
            fingerprint.mix(UInt64(item.isIncluded ? 1 : 0))
            fingerprint.mix(item.evidence?.rawValue ?? "unasked")
        }
        for weight in posterior { fingerprint.mix(weight.bitPattern) }
        fingerprint.mix(epsilonKnowledge.bitPattern)
        fingerprint.mix(evidenceReliabilityScale.bitPattern)
        for key in selection.sorted() { fingerprint.mix(key) }
        return fingerprint.hex
    }
}

private struct ObservationFingerprint {
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
