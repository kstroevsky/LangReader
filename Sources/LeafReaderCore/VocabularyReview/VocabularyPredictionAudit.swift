import Foundation

package enum VocabularyPredictionAuditAnswer: String, Codable, Equatable, Sendable {
    case known
    case unknown
}

package struct VocabularyPredictionAuditItem: Codable, Equatable, Identifiable, Sendable {
    package var id: String { canonicalKey }
    package let canonicalKey: String
    package let displayLemma: String
    package let partOfSpeech: VocabularyPartOfSpeech
    package let identityPolicy: VocabularyAssessmentIdentityPolicy
    package let occurrenceCount: Int
    package let predictedKnownProbability: Double
    package let selectedForLearning: Bool

    private enum CodingKeys: String, CodingKey {
        case canonicalKey
        case displayLemma
        case partOfSpeech
        case identityPolicy
        case occurrenceCount
        case predictedKnownProbability
        case selectedForLearning
    }

    package init(
        canonicalKey: String,
        displayLemma: String,
        partOfSpeech: VocabularyPartOfSpeech,
        identityPolicy: VocabularyAssessmentIdentityPolicy = .fullInference,
        occurrenceCount: Int,
        predictedKnownProbability: Double,
        selectedForLearning: Bool
    ) {
        self.canonicalKey = canonicalKey
        self.displayLemma = displayLemma
        self.partOfSpeech = partOfSpeech
        self.identityPolicy = identityPolicy
        self.occurrenceCount = max(0, occurrenceCount)
        self.predictedKnownProbability = min(max(predictedKnownProbability, 0), 1)
        self.selectedForLearning = selectedForLearning
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        canonicalKey = try container.decode(String.self, forKey: .canonicalKey)
        displayLemma = try container.decode(String.self, forKey: .displayLemma)
        partOfSpeech = try container.decode(VocabularyPartOfSpeech.self, forKey: .partOfSpeech)
        identityPolicy = try container.decodeIfPresent(
            VocabularyAssessmentIdentityPolicy.self,
            forKey: .identityPolicy
        ) ?? .fullInference
        occurrenceCount = max(0, try container.decode(Int.self, forKey: .occurrenceCount))
        predictedKnownProbability = min(
            max(try container.decode(Double.self, forKey: .predictedKnownProbability), 0),
            1
        )
        selectedForLearning = try container.decode(Bool.self, forKey: .selectedForLearning)
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(canonicalKey, forKey: .canonicalKey)
        try container.encode(displayLemma, forKey: .displayLemma)
        try container.encode(partOfSpeech, forKey: .partOfSpeech)
        try container.encode(identityPolicy, forKey: .identityPolicy)
        try container.encode(occurrenceCount, forKey: .occurrenceCount)
        try container.encode(predictedKnownProbability, forKey: .predictedKnownProbability)
        try container.encode(selectedForLearning, forKey: .selectedForLearning)
    }
}

package struct VocabularyPredictionAuditScoredItem: Codable, Equatable, Sendable {
    package let item: VocabularyPredictionAuditItem
    package let answer: VocabularyPredictionAuditAnswer
}

package struct VocabularyPredictionAuditCalibrationMetrics: Codable, Equatable, Sendable {
    package let itemCount: Int
    package let brierScore: Double
    package let expectedCalibrationError: Double
}

package struct VocabularyPredictionAuditResult: Codable, Equatable, Sendable {
    package let protocolVersion: Int
    package let languageCode: String
    package let mode: VocabularyAssessmentMode
    package let scoredItems: [VocabularyPredictionAuditScoredItem]
    package let predictedLearningCount: Int
    package let actualUnknownCount: Int
    package let missedUnknownCount: Int
    package let predictedLearningPrecision: Double
    package let predictedLearningRecall: Double
    package let currentLexicalTokenCoverage: Double
    package let projectedLexicalTokenCoverage: Double
    package let brierScore: Double
    package let expectedCalibrationError: Double
    package let fullInferenceCalibration: VocabularyPredictionAuditCalibrationMetrics?
    package let directEvidenceOnlyCalibration: VocabularyPredictionAuditCalibrationMetrics?
}

/// A local, complete, blind self-report audit of a frozen no-test prediction.
/// It is intentionally separate from assessment evidence, reader priors, and
/// independently scored validation-study data.
package struct VocabularyPredictionAuditSession: Codable, Equatable, Sendable {
    package static let currentProtocolVersion = 2

    package let protocolVersion: Int
    package let inventoryFingerprint: String
    package let languageCode: String
    package let mode: VocabularyAssessmentMode
    package let assessmentAlgorithmVersion: Int
    package let knowledgeModelVersion: String
    package let observationModelVersion: String
    package let items: [VocabularyPredictionAuditItem]
    package let itemKeys: Set<String>
    package private(set) var answers: [String: VocabularyPredictionAuditAnswer]
    package private(set) var nextIndex: Int

    package init(
        inventory: DocumentVocabularyInventory,
        prediction: VocabularyAssessmentResult,
        mode: VocabularyAssessmentMode,
        algorithmVersion: Int = VocabularyPreparationSession.currentAlgorithmVersion
    ) {
        let byKey = Dictionary(uniqueKeysWithValues: prediction.items.map { ($0.id, $0) })
        let fingerprint = Self.fingerprint(inventory: inventory)
        var unsortedItems: [VocabularyPredictionAuditItem] = []
        unsortedItems.reserveCapacity(inventory.candidates.count)
        for candidate in inventory.candidates {
            guard let predicted = byKey[candidate.canonicalKey] else { continue }
            unsortedItems.append(VocabularyPredictionAuditItem(
                canonicalKey: candidate.canonicalKey,
                displayLemma: candidate.displayLemma,
                partOfSpeech: candidate.partOfSpeech,
                identityPolicy: candidate.identityPolicy,
                occurrenceCount: candidate.occurrenceCount,
                predictedKnownProbability: predicted.knownProbability,
                selectedForLearning: predicted.isSelected
            ))
        }
        let decoratedItems = unsortedItems.map { item in
            (item, Self.blindOrder(fingerprint: fingerprint, canonicalKey: item.canonicalKey))
        }
        let auditItems = decoratedItems.sorted {
            $0.1 == $1.1 ? $0.0.canonicalKey < $1.0.canonicalKey : $0.1 < $1.1
        }.map(\.0)
        self.init(
            inventoryFingerprint: fingerprint,
            languageCode: inventory.languageCode,
            mode: mode,
            items: auditItems,
            algorithmVersion: algorithmVersion
        )
    }

    package init(
        inventoryFingerprint: String,
        languageCode: String,
        mode: VocabularyAssessmentMode,
        items: [VocabularyPredictionAuditItem],
        answers: [String: VocabularyPredictionAuditAnswer] = [:],
        algorithmVersion: Int = VocabularyPreparationSession.currentAlgorithmVersion
    ) {
        protocolVersion = Self.currentProtocolVersion
        self.inventoryFingerprint = inventoryFingerprint
        self.languageCode = languageCode
        self.mode = mode
        assessmentAlgorithmVersion = algorithmVersion
        knowledgeModelVersion = VocabularyKnowledgeModel.version
        observationModelVersion = VocabularyObservationModel.version
        self.items = items
        let validKeys = Set(items.map(\.canonicalKey))
        itemKeys = validKeys
        self.answers = answers.filter { validKeys.contains($0.key) }
        nextIndex = 0
        advanceNextIndex()
    }

    package var answeredCount: Int { answers.count }
    package var totalCount: Int { items.count }
    package var isComplete: Bool { !items.isEmpty && nextIndex == items.count }
    package var nextItem: VocabularyPredictionAuditItem? {
        items.indices.contains(nextIndex) ? items[nextIndex] : nil
    }

    package mutating func record(
        _ answer: VocabularyPredictionAuditAnswer,
        for canonicalKey: String
    ) {
        guard answers[canonicalKey] == nil, itemKeys.contains(canonicalKey) else { return }
        answers[canonicalKey] = answer
        advanceNextIndex()
    }

    package func isCompatible(
        inventory: DocumentVocabularyInventory,
        mode: VocabularyAssessmentMode,
        algorithmVersion: Int = VocabularyPreparationSession.currentAlgorithmVersion
    ) -> Bool {
        protocolVersion == Self.currentProtocolVersion
            && assessmentAlgorithmVersion == algorithmVersion
            && knowledgeModelVersion == VocabularyKnowledgeModel.version
            && observationModelVersion == VocabularyObservationModel.version
            && inventoryFingerprint == Self.fingerprint(inventory: inventory)
            && languageCode == inventory.languageCode
            && self.mode == mode
    }

    package func result() -> VocabularyPredictionAuditResult? {
        guard isComplete else { return nil }
        let scored = items.compactMap { item -> VocabularyPredictionAuditScoredItem? in
            answers[item.canonicalKey].map { VocabularyPredictionAuditScoredItem(item: item, answer: $0) }
        }
        let selected = scored.filter(\.item.selectedForLearning)
        let actualUnknown = scored.filter { $0.answer == .unknown }
        let selectedUnknown = selected.filter { $0.answer == .unknown }
        let missedUnknown = actualUnknown.filter { !$0.item.selectedForLearning }
        let totalOccurrences = scored.reduce(0) { $0 + $1.item.occurrenceCount }
        let knownOccurrences = scored.reduce(0) { partial, scored in
            partial + (scored.answer == .known ? scored.item.occurrenceCount : 0)
        }
        let projectedOccurrences = scored.reduce(0) { partial, scored in
            partial + (
                scored.answer == .known || scored.item.selectedForLearning
                    ? scored.item.occurrenceCount
                    : 0
            )
        }
        let brier = scored.reduce(0.0) { partial, scored in
            let target = scored.answer == .known ? 1.0 : 0.0
            return partial + pow(scored.item.predictedKnownProbability - target, 2)
        } / Double(max(1, scored.count))
        let fullInference = scored.filter { $0.item.identityPolicy == .fullInference }
        let directEvidenceOnly = scored.filter { $0.item.identityPolicy == .directEvidenceOnly }
        return VocabularyPredictionAuditResult(
            protocolVersion: protocolVersion,
            languageCode: languageCode,
            mode: mode,
            scoredItems: scored,
            predictedLearningCount: selected.count,
            actualUnknownCount: actualUnknown.count,
            missedUnknownCount: missedUnknown.count,
            predictedLearningPrecision: selected.isEmpty
                ? (actualUnknown.isEmpty ? 1 : 0)
                : Double(selectedUnknown.count) / Double(selected.count),
            predictedLearningRecall: actualUnknown.isEmpty
                ? 1
                : Double(selectedUnknown.count) / Double(actualUnknown.count),
            currentLexicalTokenCoverage: totalOccurrences > 0
                ? Double(knownOccurrences) / Double(totalOccurrences)
                : 1,
            projectedLexicalTokenCoverage: totalOccurrences > 0
                ? Double(projectedOccurrences) / Double(totalOccurrences)
                : 1,
            brierScore: brier,
            expectedCalibrationError: Self.calibrationError(scored),
            fullInferenceCalibration: Self.calibrationMetrics(fullInference),
            directEvidenceOnlyCalibration: Self.calibrationMetrics(directEvidenceOnly)
        )
    }

    private static func calibrationMetrics(
        _ scored: [VocabularyPredictionAuditScoredItem]
    ) -> VocabularyPredictionAuditCalibrationMetrics? {
        guard !scored.isEmpty else { return nil }
        let brier = scored.reduce(0.0) { partial, scored in
            let target = scored.answer == .known ? 1.0 : 0.0
            return partial + pow(scored.item.predictedKnownProbability - target, 2)
        } / Double(scored.count)
        return VocabularyPredictionAuditCalibrationMetrics(
            itemCount: scored.count,
            brierScore: brier,
            expectedCalibrationError: calibrationError(scored)
        )
    }

    private static func calibrationError(_ scored: [VocabularyPredictionAuditScoredItem]) -> Double {
        guard !scored.isEmpty else { return 0 }
        var result = 0.0
        for bin in 0..<10 {
            let lower = Double(bin) / 10
            let upper = Double(bin + 1) / 10
            let entries = scored.filter {
                $0.item.predictedKnownProbability >= lower
                    && (bin == 9
                        ? $0.item.predictedKnownProbability <= upper
                        : $0.item.predictedKnownProbability < upper)
            }
            guard !entries.isEmpty else { continue }
            let confidence = entries.reduce(0.0) {
                $0 + $1.item.predictedKnownProbability
            } / Double(entries.count)
            let accuracy = Double(entries.filter { $0.answer == .known }.count) / Double(entries.count)
            result += Double(entries.count) / Double(scored.count) * abs(confidence - accuracy)
        }
        return result
    }

    private mutating func advanceNextIndex() {
        while items.indices.contains(nextIndex),
              answers[items[nextIndex].canonicalKey] != nil {
            nextIndex += 1
        }
    }

    private static func fingerprint(inventory: DocumentVocabularyInventory) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        func mix(_ byte: UInt8) {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        for byte in inventory.languageCode.utf8 { mix(byte) }
        for candidate in inventory.candidates {
            for byte in candidate.canonicalKey.utf8 { mix(byte) }
            for byte in candidate.identityPolicy.rawValue.utf8 { mix(byte) }
            withUnsafeBytes(of: UInt64(candidate.occurrenceCount).littleEndian) { bytes in
                for byte in bytes { mix(byte) }
            }
            withUnsafeBytes(of: candidate.difficultyPrior.mean.bitPattern.littleEndian) { bytes in
                for byte in bytes { mix(byte) }
            }
            withUnsafeBytes(of: candidate.difficultyPrior.standardDeviation.bitPattern.littleEndian) { bytes in
                for byte in bytes { mix(byte) }
            }
        }
        return String(format: "%016llx", hash)
    }

    private static func blindOrder(fingerprint: String, canonicalKey: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in "\(fingerprint):\(canonicalKey)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return hash
    }
}
