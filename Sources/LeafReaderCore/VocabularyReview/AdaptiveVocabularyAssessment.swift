import Foundation

private struct VocabularyPredictiveWorkerResult: Sendable {
    let range: Range<Int>
    let maskWords: [UInt64]
    let includedIndexes: [Int]
    let totalOccurrences: Int
    let baselineTotals: [Int]
}

private final class VocabularyPredictiveWorkerBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Int: VocabularyPredictiveWorkerResult] = [:]

    func store(_ result: VocabularyPredictiveWorkerResult, worker: Int) {
        lock.withLock { results[worker] = result }
    }

    func ordered(count: Int) -> [VocabularyPredictiveWorkerResult] {
        lock.withLock { (0..<count).compactMap { results[$0] } }
    }
}

private final class VocabularySynchronizedBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    func set(_ value: Value) { lock.withLock { stored = value } }
    func value() -> Value { lock.withLock { stored } }
    func mutate(_ body: (inout Value) -> Void) { lock.withLock { body(&stored) } }
}

package enum VocabularyAssessmentMode: Codable, Equatable, Sendable {
    case allUnknown
    case targetCoverage(Double)

    package var targetCoverage: Double? {
        guard case let .targetCoverage(value) = self else { return nil }
        return min(max(value, 0), 1)
    }
}

package enum VocabularyKnowledgeEvidence: String, CaseIterable, Codable, Equatable, Sendable {
    case verifiedKnown
    case typedVerifiedKnown
    case verifiedUnknownOrPartial
    case reportedUnknown
    case unsure
    case legacyKnown
    case legacyUnknown
    case excluded

    package var reliability: Double? {
        switch self {
        case .verifiedKnown: 0.97
        case .typedVerifiedKnown: 0.98
        case .verifiedUnknownOrPartial: 0.98
        case .reportedUnknown: 0.95
        case .unsure: 0.75
        case .legacyKnown: 0.75
        case .legacyUnknown: 0.85
        case .excluded: nil
        }
    }

    package var supportsKnown: Bool {
        switch self {
        case .verifiedKnown, .typedVerifiedKnown, .legacyKnown: true
        case .verifiedUnknownOrPartial, .reportedUnknown, .unsure, .legacyUnknown, .excluded: false
        }
    }

    package var isVerifiedKnown: Bool {
        self == .verifiedKnown || self == .typedVerifiedKnown
    }

    package var isVerifiedEvidence: Bool {
        isVerifiedKnown || self == .verifiedUnknownOrPartial
    }

    /// Source compatibility for call sites that do not need the richer protocol.
    package static var known: Self { .verifiedKnown }
    package static var unknown: Self { .reportedUnknown }
}

package struct DocumentVocabularyCandidate: Codable, Equatable, Identifiable, Sendable {
    package var id: String { canonicalKey }
    package let canonicalKey: String
    package let lemmaKey: String
    package let displayLemma: String
    package let lexicalItemID: VocabularyLexicalItemID?
    package let partOfSpeech: VocabularyPartOfSpeech
    package let observedForms: [VocabularyDocumentObservedForm]
    package let occurrenceCount: Int
    package let representativeRange: VocabularyDocumentSourceRange
    package let generalFrequencyRank: Int?
    package let difficultyPrior: VocabularyItemDifficultyPrior
    package var difficulty: Double { difficultyPrior.mean }

    package init(
        canonicalKey: String,
        lemmaKey: String? = nil,
        displayLemma: String,
        lexicalItemID: VocabularyLexicalItemID? = nil,
        partOfSpeech: VocabularyPartOfSpeech = .unknown,
        observedForms: [VocabularyDocumentObservedForm],
        occurrenceCount: Int,
        representativeRange: VocabularyDocumentSourceRange,
        generalFrequencyRank: Int?,
        difficulty: Double
    ) {
        self.canonicalKey = canonicalKey
        self.lemmaKey = lemmaKey ?? VocabularyTextPolicy.canonicalVocabularyKey(displayLemma)
        self.displayLemma = displayLemma
        self.lexicalItemID = lexicalItemID
        self.partOfSpeech = partOfSpeech
        self.observedForms = observedForms
        self.occurrenceCount = occurrenceCount
        self.representativeRange = representativeRange
        self.generalFrequencyRank = generalFrequencyRank
        difficultyPrior = VocabularyItemDifficultyPrior(
            mean: difficulty,
            standardDeviation: 0,
            source: .syntheticFixture,
            version: "fixed-v1"
        )
    }

    package init(
        canonicalKey: String,
        lemmaKey: String? = nil,
        displayLemma: String,
        lexicalItemID: VocabularyLexicalItemID? = nil,
        partOfSpeech: VocabularyPartOfSpeech = .unknown,
        observedForms: [VocabularyDocumentObservedForm],
        occurrenceCount: Int,
        representativeRange: VocabularyDocumentSourceRange,
        generalFrequencyRank: Int?,
        difficultyPrior: VocabularyItemDifficultyPrior
    ) {
        self.canonicalKey = canonicalKey
        self.lemmaKey = lemmaKey ?? VocabularyTextPolicy.canonicalVocabularyKey(displayLemma)
        self.displayLemma = displayLemma
        self.lexicalItemID = lexicalItemID
        self.partOfSpeech = partOfSpeech
        self.observedForms = observedForms
        self.occurrenceCount = occurrenceCount
        self.representativeRange = representativeRange
        self.generalFrequencyRank = generalFrequencyRank
        self.difficultyPrior = difficultyPrior
    }
}

package struct DocumentVocabularyInventory: Codable, Equatable, Sendable {
    package let languageCode: String
    package let documentDomain: VocabularyDocumentDomain
    package let candidates: [DocumentVocabularyCandidate]
    package let excludedCount: Int

    package init(
        summaries: [VocabularyDocumentLemmaSummary],
        languageCode: String,
        maximumFrequencyRank: Int,
        rank: (VocabularyDocumentLemmaSummary) -> Int?
    ) {
        let valid = summaries.filter(Self.isAssessable)
        candidates = valid.map { summary in
            let resolvedRank = rank(summary)
            return DocumentVocabularyCandidate(
                canonicalKey: summary.canonicalKey,
                lemmaKey: summary.lemmaKey,
                displayLemma: summary.displayLemma,
                lexicalItemID: summary.lexicalItemID,
                partOfSpeech: summary.partOfSpeech,
                observedForms: summary.observedForms,
                occurrenceCount: summary.occurrenceCount,
                representativeRange: summary.representativeRange,
                generalFrequencyRank: resolvedRank,
                difficultyPrior: VocabularyItemDifficultyPrior.frequencyRank(
                    resolvedRank,
                    scale: VocabularyFrequencyScale(
                        sourceID: "legacy-rank-provider",
                        version: "v1",
                        maximumRank: maximumFrequencyRank
                    )
                )
            )
        }.sorted(by: Self.inventoryOrder)
        self.languageCode = languageCode
        documentDomain = .general
        excludedCount = summaries.count - valid.count
    }

    package init(
        languageCode: String,
        candidates: [DocumentVocabularyCandidate],
        excludedCount: Int = 0,
        documentDomain: VocabularyDocumentDomain = .general
    ) {
        self.languageCode = languageCode
        self.documentDomain = documentDomain
        self.candidates = candidates.sorted(by: Self.inventoryOrder)
        self.excludedCount = excludedCount
    }

    package init(
        summaries: [VocabularyDocumentLemmaSummary],
        languageCode: String,
        difficultyProvider: any DocumentVocabularyDifficultyProviding
    ) {
        let valid = summaries.filter(Self.isAssessable)
        candidates = valid.map { summary in
            let resolvedRank = difficultyProvider.bestRank(for: summary)
            return DocumentVocabularyCandidate(
                canonicalKey: summary.canonicalKey,
                lemmaKey: summary.lemmaKey,
                displayLemma: summary.displayLemma,
                lexicalItemID: summary.lexicalItemID,
                partOfSpeech: summary.partOfSpeech,
                observedForms: summary.observedForms,
                occurrenceCount: summary.occurrenceCount,
                representativeRange: summary.representativeRange,
                generalFrequencyRank: resolvedRank,
                difficultyPrior: difficultyProvider.difficultyPrior(for: summary)
            )
        }.sorted(by: Self.inventoryOrder)
        self.languageCode = languageCode
        documentDomain = .general
        excludedCount = summaries.count - valid.count
    }

    package static func difficulty(forRank rank: Int?, maximumRank: Int) -> Double {
        guard let rank, rank > 0, maximumRank > 0 else { return 4 }
        let percentile = min(max(Double(rank) / Double(maximumRank), 0.0001), 0.9999)
        return min(max(log(percentile / (1 - percentile)), -4), 4)
    }

    private static func isAssessable(_ summary: VocabularyDocumentLemmaSummary) -> Bool {
        guard !summary.isConfidentName else { return false }
        let key = summary.lemmaKey
        guard !key.isEmpty, key.count <= 64 else { return false }
        let scalars = key.unicodeScalars
        guard scalars.contains(where: CharacterSet.letters.contains) else { return false }
        guard scalars.allSatisfy({
            CharacterSet.letters.contains($0)
                || CharacterSet.nonBaseCharacters.contains($0)
                || $0 == "'" || $0 == "’" || $0 == "-"
        }) else { return false }
        guard !key.hasPrefix("-"), !key.hasSuffix("-"),
              !key.hasPrefix("'"), !key.hasSuffix("'"),
              !key.hasPrefix("’"), !key.hasSuffix("’"),
              !key.contains("--"), !key.contains("''"), !key.contains("’’") else { return false }
        let letters = key.lowercased().filter(\.isLetter)
        return letters.count < 6 || Set(letters).count > 1
    }

    private static func inventoryOrder(_ lhs: DocumentVocabularyCandidate, _ rhs: DocumentVocabularyCandidate) -> Bool {
        if lhs.occurrenceCount != rhs.occurrenceCount { return lhs.occurrenceCount > rhs.occurrenceCount }
        return lhs.canonicalKey < rhs.canonicalKey
    }
}

package enum VocabularyQuestionSelectionType: String, Codable, Equatable, Sendable {
    case initialCalibration
    case adaptiveLoss
    case tailValidation
    case calibration
}

package struct VocabularyAssessmentAnswer: Codable, Equatable, Sendable {
    package let canonicalKey: String
    package let evidence: VocabularyKnowledgeEvidence
    package let wasValidation: Bool
    package let predictedKnown: Bool?
    package let typedMeaning: String?
    package let questionOrdinal: Int?
    package let selectionType: VocabularyQuestionSelectionType?
    package let predictedKnownBeforeAnswer: Double?

    package init(
        canonicalKey: String,
        evidence: VocabularyKnowledgeEvidence,
        wasValidation: Bool = false,
        predictedKnown: Bool? = nil,
        typedMeaning: String? = nil,
        questionOrdinal: Int? = nil,
        selectionType: VocabularyQuestionSelectionType? = nil,
        predictedKnownBeforeAnswer: Double? = nil
    ) {
        self.canonicalKey = canonicalKey
        self.evidence = evidence
        self.wasValidation = wasValidation
        self.predictedKnown = predictedKnown
        self.typedMeaning = typedMeaning
        self.questionOrdinal = questionOrdinal
        self.selectionType = selectionType
        self.predictedKnownBeforeAnswer = predictedKnownBeforeAnswer
    }

    package init(
        canonicalKey: String,
        outcome: VocabularyKnowledgeEvidence,
        wasValidation: Bool = false,
        predictedKnown: Bool? = nil
    ) {
        self.init(
            canonicalKey: canonicalKey,
            evidence: outcome,
            wasValidation: wasValidation,
            predictedKnown: predictedKnown
        )
    }

    private enum CodingKeys: String, CodingKey {
        case canonicalKey
        case evidence
        case outcome
        case wasValidation
        case predictedKnown
        case typedMeaning
        case questionOrdinal
        case selectionType
        case predictedKnownBeforeAnswer
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        canonicalKey = try container.decode(String.self, forKey: .canonicalKey)
        wasValidation = try container.decodeIfPresent(Bool.self, forKey: .wasValidation) ?? false
        predictedKnown = try container.decodeIfPresent(Bool.self, forKey: .predictedKnown)
        typedMeaning = try container.decodeIfPresent(String.self, forKey: .typedMeaning)
        questionOrdinal = try container.decodeIfPresent(Int.self, forKey: .questionOrdinal)
        selectionType = try container.decodeIfPresent(VocabularyQuestionSelectionType.self, forKey: .selectionType)
        predictedKnownBeforeAnswer = try container.decodeIfPresent(Double.self, forKey: .predictedKnownBeforeAnswer)
        if let decoded = try container.decodeIfPresent(VocabularyKnowledgeEvidence.self, forKey: .evidence) {
            evidence = decoded
        } else {
            let legacy = try container.decode(String.self, forKey: .outcome)
            switch legacy {
            case "known": evidence = .legacyKnown
            case "unknown": evidence = .legacyUnknown
            case "excluded": evidence = .excluded
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .outcome,
                    in: container,
                    debugDescription: "Unknown legacy vocabulary assessment outcome: \(legacy)"
                )
            }
        }
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(canonicalKey, forKey: .canonicalKey)
        try container.encode(evidence, forKey: .evidence)
        try container.encode(wasValidation, forKey: .wasValidation)
        try container.encodeIfPresent(predictedKnown, forKey: .predictedKnown)
        try container.encodeIfPresent(typedMeaning, forKey: .typedMeaning)
        try container.encodeIfPresent(questionOrdinal, forKey: .questionOrdinal)
        try container.encodeIfPresent(selectionType, forKey: .selectionType)
        try container.encodeIfPresent(predictedKnownBeforeAnswer, forKey: .predictedKnownBeforeAnswer)
    }
}

package enum VocabularyPreparationInvitationState: String, Codable, Equatable, Sendable {
    case notOffered
    case offered
    case dismissed
    case started
    case completed
}

package struct VocabularyPreparationSession: Codable, Equatable, Sendable {
    package static let currentAlgorithmVersion = 3

    package var mode: VocabularyAssessmentMode
    package var invitationState: VocabularyPreparationInvitationState
    package var answers: [VocabularyAssessmentAnswer]
    package var finalSelection: Set<String>
    package var algorithmVersion: Int
    package var readerPriorContributionRecorded: Bool?
    package var readerPriorContributionID: String?
    package var documentDomain: VocabularyDocumentDomain?
    package var predictionAudit: VocabularyPredictionAuditSession?

    package init(
        mode: VocabularyAssessmentMode = .allUnknown,
        invitationState: VocabularyPreparationInvitationState = .notOffered,
        answers: [VocabularyAssessmentAnswer] = [],
        finalSelection: Set<String> = [],
        algorithmVersion: Int = currentAlgorithmVersion,
        readerPriorContributionRecorded: Bool? = nil,
        readerPriorContributionID: String? = nil,
        documentDomain: VocabularyDocumentDomain? = nil,
        predictionAudit: VocabularyPredictionAuditSession? = nil
    ) {
        self.mode = mode
        self.invitationState = invitationState
        self.answers = answers
        self.finalSelection = finalSelection
        self.algorithmVersion = algorithmVersion
        self.readerPriorContributionRecorded = readerPriorContributionRecorded
        self.readerPriorContributionID = readerPriorContributionID
        self.documentDomain = documentDomain
        self.predictionAudit = predictionAudit
    }
}

package enum VocabularyAssessmentClassification: String, Codable, Equatable, Sendable {
    case verifiedKnown
    case reportedUnknown
    case notSure
    case estimatedKnown
    case uncertain
    case estimatedUnknown
    case excluded
}

package enum VocabularyAssessmentStopReason: String, Codable, Equatable, Sendable {
    case exhaustedCandidates
    case lowExpectedValue
    case targetCoverageStable
    case questionLimit
}

package struct VocabularyAssessmentDiagnostics: Codable, Equatable, Sendable {
    package let estimatedTheta: Double
    package let thetaLowerBound: Double
    package let thetaUpperBound: Double
    package let conservativeCoverageLowerBound: Double
    package let skippedQuestionCount: Int
    package let bestExpectedLossReduction: Double
    package let stopReason: VocabularyAssessmentStopReason?
    package let reachedQuestionLimit: Bool
}

package struct VocabularyAssessmentResultItem: Codable, Equatable, Identifiable, Sendable {
    package var id: String { candidate.canonicalKey }
    package let candidate: DocumentVocabularyCandidate
    package let knownProbability: Double
    package let classification: VocabularyAssessmentClassification
    package let isSelected: Bool
    package let predictiveKnownMask: [UInt64]

    package init(
        candidate: DocumentVocabularyCandidate,
        knownProbability: Double,
        classification: VocabularyAssessmentClassification,
        isSelected: Bool,
        predictiveKnownMask: [UInt64] = []
    ) {
        self.candidate = candidate
        self.knownProbability = knownProbability
        self.classification = classification
        self.isSelected = isSelected
        self.predictiveKnownMask = predictiveKnownMask
    }
}

package struct VocabularyAssessmentResult: Codable, Equatable, Sendable {
    package let items: [VocabularyAssessmentResultItem]
    package let answeredQuestionCount: Int
    package let errorFloor: Double
    package let coverageQuantile: Double
    package let expectedCurrentCoverage: Double
    package let expectedCoverageAfterSelection: Double
    package let residualUncertainty: Double
    package let reachedQuestionLimit: Bool
    package let diagnostics: VocabularyAssessmentDiagnostics

    package func applyingSelection(_ selectedKeys: Set<String>) -> VocabularyAssessmentResult {
        var totalOccurrences = 0.0
        var expectedKnownOccurrences = 0.0
        let updatedItems = items.map { item -> VocabularyAssessmentResultItem in
            let selected = selectedKeys.contains(item.id) && item.classification != .excluded
            if item.classification != .excluded {
                let weight = Double(item.candidate.occurrenceCount)
                totalOccurrences += weight
                expectedKnownOccurrences += weight * (selected ? 1 : item.knownProbability)
            }
            return VocabularyAssessmentResultItem(
                candidate: item.candidate,
                knownProbability: item.knownProbability,
                classification: item.classification,
                isSelected: selected,
                predictiveKnownMask: item.predictiveKnownMask
            )
        }
        let conservativeCoverage = Self.coverageLowerBound(
            items: updatedItems,
            quantile: coverageQuantile
        )
        return VocabularyAssessmentResult(
            items: updatedItems,
            answeredQuestionCount: answeredQuestionCount,
            errorFloor: errorFloor,
            coverageQuantile: coverageQuantile,
            expectedCurrentCoverage: expectedCurrentCoverage,
            expectedCoverageAfterSelection: totalOccurrences > 0 ? expectedKnownOccurrences / totalOccurrences : 1,
            residualUncertainty: residualUncertainty,
            reachedQuestionLimit: reachedQuestionLimit,
            diagnostics: VocabularyAssessmentDiagnostics(
                estimatedTheta: diagnostics.estimatedTheta,
                thetaLowerBound: diagnostics.thetaLowerBound,
                thetaUpperBound: diagnostics.thetaUpperBound,
                conservativeCoverageLowerBound: conservativeCoverage,
                skippedQuestionCount: diagnostics.skippedQuestionCount,
                bestExpectedLossReduction: diagnostics.bestExpectedLossReduction,
                stopReason: diagnostics.stopReason,
                reachedQuestionLimit: diagnostics.reachedQuestionLimit
            )
        )
    }

    private static func coverageLowerBound(
        items: [VocabularyAssessmentResultItem],
        quantile: Double
    ) -> Double {
        let included = items.filter { $0.classification != .excluded }
        let total = Double(included.reduce(0) { $0 + $1.candidate.occurrenceCount })
        guard total > 0 else { return 1 }
        if included.contains(where: { !$0.predictiveKnownMask.isEmpty }) {
            var sampleTotals = Array(repeating: 0, count: AdaptiveVocabularyAssessment.predictiveSampleCount)
            for item in included {
                let weight = item.candidate.occurrenceCount
                if item.isSelected {
                    for sample in sampleTotals.indices { sampleTotals[sample] += weight }
                } else {
                    for sample in sampleTotals.indices where Self.maskContains(item.predictiveKnownMask, sample) {
                        sampleTotals[sample] += weight
                    }
                }
            }
            let sorted = sampleTotals.sorted()
            let index = Int((quantile * Double(sorted.count - 1)).rounded(.down))
            return Double(sorted[index]) / total
        }
        let known = included.reduce(0.0) { partial, item in
            partial + Double(item.candidate.occurrenceCount) * (item.isSelected ? 1 : item.knownProbability)
        }
        return min(1, max(0, known / total))
    }

    private static func maskContains(_ mask: [UInt64], _ sample: Int) -> Bool {
        let word = sample >> 6
        guard mask.indices.contains(word) else { return false }
        return mask[word] & (UInt64(1) << UInt64(sample & 63)) != 0
    }
}

package struct AdaptiveVocabularyAssessment: Sendable {
    private struct PendingQuestion: Sendable {
        let key: String
        let validationPrediction: Bool?
        let questionOrdinal: Int
        let selectionType: VocabularyQuestionSelectionType
        let predictedKnownBeforeAnswer: Double
    }

    private struct BestQuestionCache: Sendable {
        let key: String
        let reduction: Double
    }

    private struct ScoredQuestion: Sendable {
        let candidate: DocumentVocabularyCandidate
        let reduction: Double
    }

    private struct PredictiveCoverageSamples: Sendable {
        let knownMaskWords: [UInt64]
        let includedIndexes: [Int]
        let totalOccurrences: Int
        let baselineTotals: [Int]
        let sampleCount: Int

        var maskWordCount: Int { sampleCount / 64 }
    }

    private struct CoverageDeckStabilitySnapshot: Sendable {
        let selection: Set<String>
        let selectedOccurrences: Int
    }

    private static let thetaGrid: [Double] = stride(from: -6.0, through: 6.0001, by: 0.1).map { $0 }
    package static let predictiveSampleCount = 512
    package static let predictiveScreeningSampleCount = 128
    private static let stableDeckCardCountTolerance = 3
    private static let stableDeckChangedOccurrenceShare = 0.06
    private static let stableDeckSelectedOccurrenceShare = 0.025
    private static let gaussianQuadrature: [(node: Double, weight: Double)] = [
        (-3.190_993_201_781_527_6, 0.000_022_345_844_007_746),
        (-2.266_580_584_531_843, 0.002_789_141_321_231_767),
        (-1.468_553_289_216_668, 0.049_916_406_765_217_87),
        (-0.723_551_018_752_837_6, 0.244_097_502_894_939_44),
        (0, 0.406_349_206_349_206_35),
        (0.723_551_018_752_837_6, 0.244_097_502_894_939_44),
        (1.468_553_289_216_668, 0.049_916_406_765_217_87),
        (2.266_580_584_531_843, 0.002_789_141_321_231_767),
        (3.190_993_201_781_527_6, 0.000_022_345_844_007_746)
    ]
    private let inventory: DocumentVocabularyInventory
    private let candidateIndexByKey: [String: Int]
    private let responseCurves: [[Double]]
    private let difficultyOrderedIndexes: [Int]
    private let predictiveSeed: UInt64
    private let initialPosterior: [Double]
    private let modelConfiguration: VocabularyAssessmentModelConfiguration
    private(set) package var mode: VocabularyAssessmentMode
    private(set) package var answers: [VocabularyAssessmentAnswer]
    private(set) package var epsilonKnowledge: Double
    /// Compatibility projection for existing diagnostics and callers. The value
    /// now belongs only to the latent-knowledge model.
    package var errorFloor: Double { epsilonKnowledge }
    private var posterior: [Double]
    private var answerByKey: [String: VocabularyAssessmentAnswer]
    private var answeredCandidateIndexes: Set<Int>
    private var excludedCandidateIndexes: Set<Int>
    private var answeredProbabilities: [String: Double]
    private var currentProbabilities: [Double]
    private var pendingQuestion: PendingQuestion?
    private var skippedQuestionKeys = Set<String>()
    private var lowValueStreak = 0
    private var stableCoverageDeckStreak = 0
    private var previousCoverageDeck: CoverageDeckStabilitySnapshot?
    private var previousScreeningCoverageDeck: CoverageDeckStabilitySnapshot?
    private var screeningCoverageDeckStreak = 0
    private var suppressStoppingUpdateOnce = false
    private var cachedBestQuestion: BestQuestionCache?
    private var cachedPredictiveSamples: PredictiveCoverageSamples?
    private var cachedCoverageSelection: Set<String>?
    private var cachedCoverageTargetReached: Bool
    private let usesEligibleReaderPrior: Bool
    private(set) package var screeningCoverageComputationCount = 0
    private(set) package var fullCoverageComputationCount = 0

    package init(
        inventory: DocumentVocabularyInventory,
        mode: VocabularyAssessmentMode,
        restoredAnswers: [VocabularyAssessmentAnswer] = [],
        readerPrior: VocabularyReaderPrior? = nil,
        currentDate: Date = Date(),
        modelConfiguration: VocabularyAssessmentModelConfiguration = .production
    ) {
        self.inventory = inventory
        self.mode = mode
        self.modelConfiguration = modelConfiguration
        epsilonKnowledge = modelConfiguration.minimumEpsilonKnowledge
        candidateIndexByKey = Dictionary(uniqueKeysWithValues: inventory.candidates.enumerated().map {
            ($0.element.canonicalKey, $0.offset)
        })
        responseCurves = inventory.candidates.map { candidate in
            Self.thetaGrid.map { theta in
                Self.baseItemProbability(theta: theta, difficultyPrior: candidate.difficultyPrior)
            }
        }
        difficultyOrderedIndexes = inventory.candidates.indices.sorted {
            Self.difficultyOrder(inventory.candidates[$0], inventory.candidates[$1])
        }
        predictiveSeed = Self.inventorySeed(inventory)
        answers = []
        let genericPrior = Self.normalPrior()
        usesEligibleReaderPrior = readerPrior?.languageCode == inventory.languageCode.lowercased()
            && readerPrior?.algorithmVersion == VocabularyPreparationSession.currentAlgorithmVersion
            && readerPrior?.isEligible(at: currentDate) == true
        initialPosterior = usesEligibleReaderPrior
            ? readerPrior?.warmStartPosterior(
                thetaGrid: Self.thetaGrid,
                genericPrior: genericPrior,
                warmPriorWeight: modelConfiguration.warmPriorWeight
            ) ?? genericPrior
            : genericPrior
        posterior = initialPosterior
        answerByKey = [:]
        answeredCandidateIndexes = []
        excludedCandidateIndexes = []
        answeredProbabilities = [:]
        currentProbabilities = []
        cachedCoverageSelection = nil
        cachedCoverageTargetReached = false
        currentProbabilities = probabilities(for: posterior)
        for answer in restoredAnswers {
            if candidateIndexByKey[answer.canonicalKey] != nil {
                apply(answer)
                continue
            }
            guard let migrated = inventory.candidates.first(where: { $0.lemmaKey == answer.canonicalKey }) else {
                continue
            }
            apply(VocabularyAssessmentAnswer(
                canonicalKey: migrated.canonicalKey,
                evidence: answer.evidence,
                wasValidation: answer.wasValidation,
                predictedKnown: answer.predictedKnown,
                typedMeaning: answer.typedMeaning,
                questionOrdinal: answer.questionOrdinal,
                selectionType: answer.selectionType,
                predictedKnownBeforeAnswer: answer.predictedKnownBeforeAnswer
            ))
        }
        refreshStoppingState()
    }

    package var answeredQuestionCount: Int {
        answers.lazy.filter { $0.evidence != .excluded }.count
    }

    private var minimumQuestionCount: Int {
        usesEligibleReaderPrior && validationAnswerCount >= 2 ? 8 : 20
    }

    private var validationAnswerCount: Int {
        answers.lazy.filter { $0.wasValidation && $0.evidence != .excluded }.count
    }

    package var isFinished: Bool {
        if answeredQuestionCount >= 80 { return true }
        let remaining = answerableCandidates
        let minimumAnswerCount = min(minimumQuestionCount, answeredQuestionCount + remaining.count)
        guard answeredQuestionCount >= minimumAnswerCount else { return false }
        if remaining.isEmpty { return true }
        switch mode {
        case .allUnknown:
            return lowValueStreak >= 3
        case .targetCoverage:
            return stableCoverageDeckStreak >= 3
                && cachedCoverageTargetReached
        }
    }

    package mutating func setMode(_ mode: VocabularyAssessmentMode) {
        self.mode = mode
        lowValueStreak = 0
        stableCoverageDeckStreak = 0
        previousCoverageDeck = nil
        screeningCoverageDeckStreak = 0
        previousScreeningCoverageDeck = nil
        cachedBestQuestion = nil
        cachedPredictiveSamples = nil
        cachedCoverageSelection = nil
        cachedCoverageTargetReached = false
        screeningCoverageComputationCount = 0
        fullCoverageComputationCount = 0
        refreshStoppingState()
    }

    package mutating func nextQuestion() -> DocumentVocabularyCandidate? {
        if let pendingQuestion {
            return candidate(for: pendingQuestion.key)
        }
        guard !isFinished else { return nil }
        let remaining = answerableCandidates
        guard !remaining.isEmpty else { return nil }

        let questionNumber = answeredQuestionCount + 1
        let selected: (
            candidate: DocumentVocabularyCandidate,
            validationPrediction: Bool?,
            selectionType: VocabularyQuestionSelectionType
        )
        if usesEligibleReaderPrior,
           (questionNumber == 4 || questionNumber == 8),
           let validation = validationCandidate(from: remaining) {
            selected = (validation.0, validation.1, .tailValidation)
        } else if questionNumber <= 8 {
            let fraction = (Double(questionNumber) - 0.5) / 8.0
            let orderedIndex = min(
                difficultyOrderedIndexes.count - 1,
                max(0, Int((fraction * Double(difficultyOrderedIndexes.count)).rounded(.down)))
            )
            let targetDifficulty = inventory.candidates[difficultyOrderedIndexes[orderedIndex]].difficulty
            let nearest = remaining.min {
                let lhs = abs($0.difficulty - targetDifficulty)
                let rhs = abs($1.difficulty - targetDifficulty)
                if lhs != rhs { return lhs < rhs }
                return $0.canonicalKey < $1.canonicalKey
            } ?? remaining[0]
            selected = (nearest, nil, .initialCalibration)
        } else if questionNumber > 10, questionNumber.isMultiple(of: 5), let validation = validationCandidate(from: remaining) {
            selected = (validation.0, validation.1, .tailValidation)
        } else {
            let adaptive: DocumentVocabularyCandidate
            if let cachedBestQuestion,
               let cached = candidate(for: cachedBestQuestion.key),
               answerByKey[cached.canonicalKey] == nil,
               !skippedQuestionKeys.contains(cached.canonicalKey) {
                adaptive = cached
            } else {
                adaptive = bestQuestion(from: shortlist(from: remaining)).candidate
            }
            selected = (adaptive, nil, .adaptiveLoss)
        }
        let candidateIndex = candidateIndexByKey[selected.candidate.canonicalKey]
        pendingQuestion = PendingQuestion(
            key: selected.candidate.canonicalKey,
            validationPrediction: selected.validationPrediction,
            questionOrdinal: questionNumber,
            selectionType: selected.selectionType,
            predictedKnownBeforeAnswer: candidateIndex.map { currentProbabilities[$0] } ?? 0.5
        )
        return selected.candidate
    }

    package mutating func record(
        _ evidence: VocabularyKnowledgeEvidence,
        for canonicalKey: String,
        typedMeaning: String? = nil
    ) {
        guard candidateIndexByKey[canonicalKey] != nil, answerByKey[canonicalKey] == nil else { return }
        cachedBestQuestion = nil
        let pending = pendingQuestion?.key == canonicalKey ? pendingQuestion : nil
        let answer = VocabularyAssessmentAnswer(
            canonicalKey: canonicalKey,
            evidence: evidence,
            wasValidation: pending?.validationPrediction != nil,
            predictedKnown: pending?.validationPrediction,
            typedMeaning: typedMeaning,
            questionOrdinal: pending?.questionOrdinal,
            selectionType: pending?.selectionType,
            predictedKnownBeforeAnswer: pending?.predictedKnownBeforeAnswer
        )
        apply(answer)
        pendingQuestion = nil
        refreshStoppingState(afterAnsweredKey: evidence == .excluded ? nil : canonicalKey)
    }

    package var thetaPosteriorSnapshot: [Double] { posterior }

    package var predictiveUniqueThetaSampleCount: Int {
        let indexes = stratifiedThetaSampleIndexes(sampleCount: Self.predictiveSampleCount)
        guard var previous = indexes.first else { return 0 }
        var count = 1
        for index in indexes.dropFirst() where index != previous {
            count += 1
            previous = index
        }
        return count
    }

    package var verifiedEvidenceCount: Int {
        answers.lazy.filter { $0.evidence.isVerifiedEvidence }.count
    }

    package var usedEligibleReaderPrior: Bool { usesEligibleReaderPrior }
    package var requiredMinimumAnsweredQuestionCount: Int { minimumQuestionCount }

    /// Skips a dictionary-failure item without treating it as an answer or an
    /// exclusion. It remains an unasked posterior item in the final result.
    package mutating func skipCurrentQuestion() {
        guard let pendingQuestion else { return }
        skippedQuestionKeys.insert(pendingQuestion.key)
        self.pendingQuestion = nil
        cachedBestQuestion = nil
        refreshStoppingState()
    }

    package func knownProbability(for canonicalKey: String) -> Double? {
        guard let index = candidateIndexByKey[canonicalKey] else { return nil }
        if let answer = answerByKey[canonicalKey] {
            return answer.evidence == .excluded ? nil : answeredProbabilities[canonicalKey]
        }
        return currentProbabilities[index]
    }

    /// Exposes the exact decision objective for deterministic evaluator and
    /// oracle tests without exposing the posterior representation itself.
    package func expectedLossReduction(for canonicalKey: String) -> Double? {
        guard answerByKey[canonicalKey] == nil,
              !skippedQuestionKeys.contains(canonicalKey),
              let candidate = candidate(for: canonicalKey) else { return nil }
        return bestQuestion(from: [candidate]).reduction
    }

    package func result(selectionOverride: Set<String>? = nil) -> VocabularyAssessmentResult {
        let predictiveSamples = cachedPredictiveSamples ?? predictiveCoverageSamples()
        let proposed = proposedSelection(
            predictiveSamples: predictiveSamples,
            pruneRedundant: true
        )
        let selection = selectionOverride ?? proposed
        var totalOccurrences = 0.0
        var expectedCurrentKnownOccurrences = 0.0
        var expectedKnownOccurrences = 0.0
        let items = inventory.candidates.enumerated().map { index, candidate -> VocabularyAssessmentResultItem in
            let answer = answerByKey[candidate.canonicalKey]
            let probability = knownProbability(for: candidate.canonicalKey) ?? 0
            let classification: VocabularyAssessmentClassification
            switch answer?.evidence {
            case .verifiedKnown, .typedVerifiedKnown: classification = .verifiedKnown
            case .verifiedUnknownOrPartial, .reportedUnknown, .legacyUnknown: classification = .reportedUnknown
            case .unsure: classification = .notSure
            case .legacyKnown:
                if probability >= 0.85 { classification = .estimatedKnown }
                else if probability <= 0.15 { classification = .estimatedUnknown }
                else { classification = .uncertain }
            case .excluded: classification = .excluded
            case nil:
                if probability >= 0.85 { classification = .estimatedKnown }
                else if probability <= 0.15 { classification = .estimatedUnknown }
                else { classification = .uncertain }
            }
            if classification != .excluded {
                let weight = Double(candidate.occurrenceCount)
                totalOccurrences += weight
                expectedCurrentKnownOccurrences += weight * probability
                expectedKnownOccurrences += weight * (selection.contains(candidate.canonicalKey) ? 1 : probability)
            }
            return VocabularyAssessmentResultItem(
                candidate: candidate,
                knownProbability: probability,
                classification: classification,
                isSelected: classification != .excluded && selection.contains(candidate.canonicalKey),
                predictiveKnownMask: Array(
                    predictiveSamples.knownMaskWords[
                        (index * predictiveSamples.maskWordCount)..<((index + 1) * predictiveSamples.maskWordCount)
                    ]
                )
            )
        }
        let uncertainty = items.reduce(0.0) { partial, item in
            guard item.classification != .excluded else { return partial }
            return partial + min(item.knownProbability, 1 - item.knownProbability)
        }
        let reachedQuestionLimit = answeredQuestionCount >= 80
        let lowerTheta = posteriorQuantile(0.05)
        let upperTheta = posteriorQuantile(0.95)
        let bestReduction = bestAvailableQuestionReduction()
        let diagnostics = VocabularyAssessmentDiagnostics(
            estimatedTheta: posteriorMean(),
            thetaLowerBound: lowerTheta,
            thetaUpperBound: upperTheta,
            conservativeCoverageLowerBound: coverageLowerBound(
                selection: selection,
                predictiveSamples: predictiveSamples
            ),
            skippedQuestionCount: skippedQuestionKeys.count,
            bestExpectedLossReduction: bestReduction,
            stopReason: stopReason,
            reachedQuestionLimit: reachedQuestionLimit
        )
        return VocabularyAssessmentResult(
            items: items,
            answeredQuestionCount: answeredQuestionCount,
            errorFloor: epsilonKnowledge,
            coverageQuantile: modelConfiguration.coverageQuantile,
            expectedCurrentCoverage: totalOccurrences > 0
                ? expectedCurrentKnownOccurrences / totalOccurrences
                : 1,
            expectedCoverageAfterSelection: totalOccurrences > 0 ? expectedKnownOccurrences / totalOccurrences : 1,
            residualUncertainty: uncertainty,
            reachedQuestionLimit: reachedQuestionLimit,
            diagnostics: diagnostics
        )
    }

    private var unaskedCandidates: [DocumentVocabularyCandidate] {
        inventory.candidates.indices.compactMap {
            answeredCandidateIndexes.contains($0) ? nil : inventory.candidates[$0]
        }
    }

    private var answerableCandidates: [DocumentVocabularyCandidate] {
        unaskedCandidates.filter { !skippedQuestionKeys.contains($0.canonicalKey) }
    }

    private var stopReason: VocabularyAssessmentStopReason? {
        if answeredQuestionCount >= 80 { return .questionLimit }
        let remaining = answerableCandidates
        let minimumAnswerCount = min(minimumQuestionCount, answeredQuestionCount + remaining.count)
        guard answeredQuestionCount >= minimumAnswerCount else { return nil }
        if remaining.isEmpty { return .exhaustedCandidates }
        switch mode {
        case .allUnknown:
            return lowValueStreak >= 3 ? .lowExpectedValue : nil
        case .targetCoverage:
            return stableCoverageDeckStreak >= 3
                && cachedCoverageTargetReached
                ? .targetCoverageStable
                : nil
        }
    }

    private mutating func apply(_ answer: VocabularyAssessmentAnswer) {
        guard answerByKey[answer.canonicalKey] == nil else { return }
        answers.append(answer)
        answerByKey[answer.canonicalKey] = answer
        if let index = candidateIndexByKey[answer.canonicalKey] {
            answeredCandidateIndexes.insert(index)
            if answer.evidence == .excluded { excludedCandidateIndexes.insert(index) }
        }
        guard answer.evidence != .excluded,
              candidateIndexByKey[answer.canonicalKey] != nil else { return }

        if let predictedKnown = answer.predictedKnown {
            let contradiction = Self.contradictionAmount(
                evidence: answer.evidence,
                predictedKnown: predictedKnown
            )
            let validations = answers.filter { $0.predictedKnown != nil && $0.evidence != .excluded }
            let contradictions = validations.reduce(0.0) { partial, validation in
                guard let prediction = validation.predictedKnown else { return partial }
                return partial + Self.contradictionAmount(
                    evidence: validation.evidence,
                    predictedKnown: prediction
                )
            }
            let smoothedRate = (contradictions + 1) / Double(validations.count + 20)
            epsilonKnowledge = min(
                0.25,
                max(modelConfiguration.minimumEpsilonKnowledge, smoothedRate)
            )
            if contradiction > 0 && answeredQuestionCount >= 20 {
                lowValueStreak = 0
                stableCoverageDeckStreak = 0
                screeningCoverageDeckStreak = 0
                suppressStoppingUpdateOnce = true
            }
        }

        rebuildPosterior()
    }

    private mutating func rebuildPosterior() {
        posterior = initialPosterior
        cachedPredictiveSamples = nil
        cachedCoverageSelection = nil
        cachedCoverageTargetReached = false
        for answer in answers where answer.evidence != .excluded {
            guard let candidateIndex = candidateIndexByKey[answer.canonicalKey] else { continue }
            for index in posterior.indices {
                let latentKnown = VocabularyKnowledgeModel.adjustedKnownProbability(
                    baseKnownProbability: responseCurves[candidateIndex][index],
                    epsilonKnowledge: epsilonKnowledge
                )
                posterior[index] *= VocabularyObservationModel.evidenceLikelihood(
                    evidence: answer.evidence,
                    latentKnownProbability: latentKnown,
                    reliabilityScale: modelConfiguration.evidenceReliabilityScale
                )
            }
            Self.normalize(&posterior)
        }
        currentProbabilities = probabilities(for: posterior)
        rebuildAnsweredProbabilities()
    }

    private mutating func refreshStoppingState(afterAnsweredKey answeredKey: String? = nil) {
        cachedBestQuestion = nil
        let stoppingUpdateWasSuppressed = suppressStoppingUpdateOnce
        suppressStoppingUpdateOnce = false
        let advancesStoppingStreak = answeredKey != nil && !stoppingUpdateWasSuppressed
        let remaining = answerableCandidates
        let minimumAnswerCount = min(minimumQuestionCount, answeredQuestionCount + remaining.count)
        guard answeredQuestionCount < 80,
              answeredQuestionCount >= minimumAnswerCount,
              !remaining.isEmpty else { return }
        switch mode {
        case .allUnknown:
            let best = bestQuestion(from: shortlist(from: remaining))
            cachedBestQuestion = BestQuestionCache(key: best.candidate.canonicalKey, reduction: best.reduction)
            if advancesStoppingStreak {
                lowValueStreak = best.reduction < 0.25 ? lowValueStreak + 1 : 0
            }
        case .targetCoverage:
            let snapshot = self
            let samplesBox = VocabularySynchronizedBox<PredictiveCoverageSamples?>(nil)
            let deckBox = VocabularySynchronizedBox<Set<String>?>(nil)
            let questionBox = VocabularySynchronizedBox<BestQuestionCache?>(nil)
            let stoppingSampleCount = modelConfiguration.coverageStoppingComputation == .staged
                ? Self.predictiveScreeningSampleCount
                : Self.predictiveSampleCount
            DispatchQueue.concurrentPerform(iterations: 2) { operation in
                if operation == 0 {
                    let samples = snapshot.predictiveCoverageSamples(sampleCount: stoppingSampleCount)
                    samplesBox.set(samples)
                    deckBox.set(snapshot.proposedSelection(predictiveSamples: samples))
                } else {
                    let best = snapshot.bestQuestion(from: snapshot.shortlist(from: remaining))
                    questionBox.set(BestQuestionCache(
                        key: best.candidate.canonicalKey,
                        reduction: best.reduction
                    ))
                }
            }
            guard let samples = samplesBox.value(), let deck = deckBox.value() else { return }
            cachedBestQuestion = questionBox.value()
            let currentSnapshot = CoverageDeckStabilitySnapshot(
                selection: deck,
                selectedOccurrences: selectedOccurrences(in: deck)
            )
            if modelConfiguration.coverageStoppingComputation == .fullEveryAnswer {
                fullCoverageComputationCount += 1
                cachedPredictiveSamples = samples
                cachedCoverageSelection = deck
                cachedCoverageTargetReached = true
                if advancesStoppingStreak {
                    stableCoverageDeckStreak = previousCoverageDeck.map {
                        let isStable = usesEligibleReaderPrior
                            ? coverageDeckIsMateriallyStable(
                                previous: $0,
                                current: currentSnapshot,
                                normalizing: answeredKey,
                                totalOccurrences: samples.totalOccurrences
                            )
                            : $0.selection == currentSnapshot.selection
                        return isStable ? stableCoverageDeckStreak + 1 : 0
                    } ?? 0
                }
                previousCoverageDeck = currentSnapshot
                return
            }

            screeningCoverageComputationCount += 1
            cachedCoverageTargetReached = false
            stableCoverageDeckStreak = 0
            if advancesStoppingStreak {
                screeningCoverageDeckStreak = previousScreeningCoverageDeck.map {
                    let isStable = usesEligibleReaderPrior
                        ? coverageDeckIsMateriallyStable(
                            previous: $0,
                            current: currentSnapshot,
                            normalizing: answeredKey,
                            totalOccurrences: samples.totalOccurrences
                        )
                        : $0.selection == currentSnapshot.selection
                    return isStable ? screeningCoverageDeckStreak + 1 : 0
                } ?? 0
            }
            previousScreeningCoverageDeck = currentSnapshot
            guard screeningCoverageDeckStreak >= 3 else { return }

            let fullSamples = predictiveCoverageSamples()
            let fullDeck = proposedSelection(predictiveSamples: fullSamples)
            fullCoverageComputationCount += 1
            let fullSnapshot = CoverageDeckStabilitySnapshot(
                selection: fullDeck,
                selectedOccurrences: selectedOccurrences(in: fullDeck)
            )
            cachedPredictiveSamples = fullSamples
            cachedCoverageSelection = fullDeck
            cachedCoverageTargetReached = true
            stableCoverageDeckStreak = 3
            previousCoverageDeck = fullSnapshot
        }
    }

    private func coverageDeckIsMateriallyStable(
        previous: CoverageDeckStabilitySnapshot,
        current: CoverageDeckStabilitySnapshot,
        normalizing answeredKey: String?,
        totalOccurrences: Int
    ) -> Bool {
        let previousKeys = answeredKey.map { previous.selection.subtracting([$0]) } ?? previous.selection
        let currentKeys = answeredKey.map { current.selection.subtracting([$0]) } ?? current.selection
        let cardCountDelta = abs(previousKeys.count - currentKeys.count)
        let changedOccurrences = previousKeys.symmetricDifference(currentKeys).reduce(0) { partial, key in
            guard let index = candidateIndexByKey[key] else { return partial }
            return partial + inventory.candidates[index].occurrenceCount
        }
        let changedOccurrenceTolerance = max(
            1,
            Int(ceil(Double(totalOccurrences) * Self.stableDeckChangedOccurrenceShare))
        )
        let selectedOccurrenceTolerance = max(
            1,
            Int(ceil(Double(totalOccurrences) * Self.stableDeckSelectedOccurrenceShare))
        )
        let answeredOccurrences = answeredKey.flatMap { candidateIndexByKey[$0] }.map {
            inventory.candidates[$0].occurrenceCount
        } ?? 0
        let previousOccurrences = previous.selectedOccurrences
            - (answeredKey.map(previous.selection.contains) == true ? answeredOccurrences : 0)
        let currentOccurrences = current.selectedOccurrences
            - (answeredKey.map(current.selection.contains) == true ? answeredOccurrences : 0)
        return cardCountDelta <= Self.stableDeckCardCountTolerance
            && changedOccurrences <= changedOccurrenceTolerance
            && abs(previousOccurrences - currentOccurrences) <= selectedOccurrenceTolerance
    }

    private func selectedOccurrences(in selection: Set<String>) -> Int {
        selection.reduce(0) { partial, key in
            guard let index = candidateIndexByKey[key] else { return partial }
            return partial + inventory.candidates[index].occurrenceCount
        }
    }

    private func proposedSelection(
        predictiveSamples suppliedSamples: PredictiveCoverageSamples? = nil,
        pruneRedundant: Bool = false
    ) -> Set<String> {
        let eligible = inventory.candidates.filter { candidate in
            answerByKey[candidate.canonicalKey]?.evidence != .excluded
        }
        let probabilities = Dictionary(uniqueKeysWithValues: eligible.compactMap { candidate -> (String, Double)? in
            knownProbability(for: candidate.canonicalKey).map { (candidate.canonicalKey, $0) }
        })
        switch mode {
        case .allUnknown:
            return Set(eligible.compactMap { candidate -> String? in
                guard let probability = probabilities[candidate.canonicalKey] else { return nil }
                return probability < 0.5 ? candidate.canonicalKey : nil
            })
        case let .targetCoverage(target):
            if suppliedSamples == nil, let cachedCoverageSelection { return cachedCoverageSelection }
            let samples = suppliedSamples ?? cachedPredictiveSamples ?? predictiveCoverageSamples()
            return coverageSelection(target: target, samples: samples, pruneRedundant: pruneRedundant)
        }
    }

    private func coverageLowerBound(
        selection: Set<String>,
        predictiveSamples suppliedSamples: PredictiveCoverageSamples? = nil
    ) -> Double {
        let samples = suppliedSamples ?? cachedPredictiveSamples ?? predictiveCoverageSamples()
        guard samples.totalOccurrences > 0 else { return 1 }
        var totals = baselineCoverageTotals(samples)
        for index in samples.includedIndexes where selection.contains(inventory.candidates[index].canonicalKey) {
            addLearningGain(candidateIndex: index, samples: samples, totals: &totals)
        }
        return Self.coverageLowerBound(
            totals: totals,
            totalOccurrences: samples.totalOccurrences,
            quantile: modelConfiguration.coverageQuantile
        )
    }

    private func predictiveCoverageSamples(
        sampleCount: Int = Self.predictiveSampleCount
    ) -> PredictiveCoverageSamples {
        precondition(sampleCount > 0 && sampleCount.isMultiple(of: 64))
        let maskWordCount = sampleCount / 64
        let thetaSampleIndexes = stratifiedThetaSampleIndexes(sampleCount: sampleCount)
        let candidateCount = inventory.candidates.count
        let workerCount = candidateCount >= 1_000 ? 4 : 1
        let buffer = VocabularyPredictiveWorkerBuffer()
        DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
            let lower = candidateCount * worker / workerCount
            let upper = candidateCount * (worker + 1) / workerCount
            let range = lower..<upper
            var localMasks = Array(repeating: UInt64(0), count: range.count * maskWordCount)
            var localIncluded: [Int] = []
            var localTotal = 0
            var localBaseline = Array(repeating: 0, count: sampleCount)
            var randomState = predictiveSeed
                ^ (UInt64(worker + 1) &* 0x9E37_79B9_7F4A_7C15)
            if randomState == 0 { randomState = 0xA076_1D64_78BD_642F }
            for candidateIndex in range {
                let candidate = inventory.candidates[candidateIndex]
                if answerByKey[candidate.canonicalKey]?.evidence == .excluded { continue }
                localIncluded.append(candidateIndex)
                localTotal += candidate.occurrenceCount
                let evidence = answerByKey[candidate.canonicalKey]?.evidence
                let localMaskOffset = (candidateIndex - lower) * maskWordCount
                let curve = responseCurves[candidateIndex]
                if let evidence {
                    var previousThetaIndex = -1
                    var probability = 0.0
                    for sampleIndex in 0..<sampleCount {
                        let thetaIndex = thetaSampleIndexes[sampleIndex]
                        if thetaIndex != previousThetaIndex
                            || !modelConfiguration.reuseRepeatedPredictiveProbabilities {
                            let latentKnown = VocabularyKnowledgeModel.adjustedKnownProbability(
                                baseKnownProbability: curve[thetaIndex],
                                epsilonKnowledge: epsilonKnowledge
                            )
                            probability = VocabularyObservationModel.posteriorKnownProbability(
                                prior: latentKnown,
                                evidence: evidence,
                                reliabilityScale: modelConfiguration.evidenceReliabilityScale
                            )
                            previousThetaIndex = thetaIndex
                        }
                        if Self.nextRandomUnit(state: &randomState) < probability {
                            localMasks[localMaskOffset + (sampleIndex >> 6)] |= UInt64(1) << UInt64(sampleIndex & 63)
                            localBaseline[sampleIndex] += candidate.occurrenceCount
                        }
                    }
                } else {
                    var previousThetaIndex = -1
                    var probability = 0.0
                    for sampleIndex in 0..<sampleCount {
                        let thetaIndex = thetaSampleIndexes[sampleIndex]
                        if thetaIndex != previousThetaIndex
                            || !modelConfiguration.reuseRepeatedPredictiveProbabilities {
                            probability = VocabularyKnowledgeModel.adjustedKnownProbability(
                                baseKnownProbability: curve[thetaIndex],
                                epsilonKnowledge: epsilonKnowledge
                            )
                            previousThetaIndex = thetaIndex
                        }
                        if Self.nextRandomUnit(state: &randomState) < probability {
                            localMasks[localMaskOffset + (sampleIndex >> 6)] |= UInt64(1) << UInt64(sampleIndex & 63)
                            localBaseline[sampleIndex] += candidate.occurrenceCount
                        }
                    }
                }
            }
            buffer.store(
                VocabularyPredictiveWorkerResult(
                    range: range,
                    maskWords: localMasks,
                    includedIndexes: localIncluded,
                    totalOccurrences: localTotal,
                    baselineTotals: localBaseline
                ),
                worker: worker
            )
        }
        var maskWords = Array(repeating: UInt64(0), count: candidateCount * maskWordCount)
        var includedIndexes: [Int] = []
        var totalOccurrences = 0
        var baselineTotals = Array(repeating: 0, count: sampleCount)
        for result in buffer.ordered(count: workerCount) {
            let destination = (result.range.lowerBound * maskWordCount)..<(result.range.upperBound * maskWordCount)
            maskWords.replaceSubrange(destination, with: result.maskWords)
            includedIndexes.append(contentsOf: result.includedIndexes)
            totalOccurrences += result.totalOccurrences
            for sample in baselineTotals.indices {
                baselineTotals[sample] += result.baselineTotals[sample]
            }
        }
        return PredictiveCoverageSamples(
            knownMaskWords: maskWords,
            includedIndexes: includedIndexes,
            totalOccurrences: totalOccurrences,
            baselineTotals: baselineTotals,
            sampleCount: sampleCount
        )
    }

    private func stratifiedThetaSampleIndexes(sampleCount: Int) -> [Int] {
        var cumulative: [Double] = []
        cumulative.reserveCapacity(posterior.count)
        var running = 0.0
        for weight in posterior {
            running += weight
            cumulative.append(running)
        }
        var gridIndex = 0
        return (0..<sampleCount).map { sampleIndex in
            let quantile = (Double(sampleIndex) + 0.5) / Double(sampleCount)
            while gridIndex < cumulative.count - 1, cumulative[gridIndex] < quantile {
                gridIndex += 1
            }
            return gridIndex
        }
    }

    private func coverageSelection(
        target: Double,
        samples: PredictiveCoverageSamples,
        pruneRedundant: Bool
    ) -> Set<String> {
        let target = min(max(target, 0), 1)
        guard samples.totalOccurrences > 0 else { return [] }
        let baseline = baselineCoverageTotals(samples)
        if Self.coverageLowerBound(
            totals: baseline,
            totalOccurrences: samples.totalOccurrences,
            quantile: modelConfiguration.coverageQuantile
        ) >= target { return [] }

        if samples.includedIndexes.count <= 10,
           let exact = exactCoverageSelection(target: target, samples: samples, baseline: baseline) {
            return exact
        }

        let tailCount = max(
            1,
            Int(ceil(modelConfiguration.coverageQuantile * Double(samples.sampleCount)))
        )
        let worstSamples = baseline.indices.sorted {
            if baseline[$0] != baseline[$1] { return baseline[$0] < baseline[$1] }
            return $0 < $1
        }.prefix(tailCount)
        let ranked = samples.includedIndexes.map { index -> (Int, Int) in
            let weight = inventory.candidates[index].occurrenceCount
            let gain = worstSamples.reduce(0) { partial, sample in
                partial + (Self.maskContains(samples, candidateIndex: index, sample: sample) ? 0 : weight)
            }
            return (index, gain)
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            let lhs = inventory.candidates[$0.0]
            let rhs = inventory.candidates[$1.0]
            if lhs.occurrenceCount != rhs.occurrenceCount { return lhs.occurrenceCount > rhs.occurrenceCount }
            return lhs.canonicalKey < rhs.canonicalKey
        }

        let workerCount = min(4, samples.maskWordCount)
        let requiredBox = VocabularySynchronizedBox<[Int: [Int]]>([:])
        DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
            let lowerWord = samples.maskWordCount * worker / workerCount
            let upperWord = samples.maskWordCount * (worker + 1) / workerCount
            var required: [Int] = []
            required.reserveCapacity((upperWord - lowerWord) * 64)
            for wordIndex in lowerWord..<upperWord {
                let sampleOffset = wordIndex * 64
                var covered = Array(baseline[sampleOffset..<(sampleOffset + 64)])
                var requiredInWord = Array(repeating: ranked.count, count: 64)
                var activeBits = UInt64.max
                for (position, entry) in ranked.enumerated() where activeBits != 0 {
                    let candidateIndex = entry.0
                    var unknownBits = ~samples.knownMaskWords[
                        candidateIndex * samples.maskWordCount + wordIndex
                    ]
                        & activeBits
                    let weight = inventory.candidates[candidateIndex].occurrenceCount
                    while unknownBits != 0 {
                        let bit = unknownBits.trailingZeroBitCount
                        covered[bit] += weight
                        if Double(covered[bit]) / Double(samples.totalOccurrences) >= target {
                            requiredInWord[bit] = position + 1
                            activeBits &= ~(UInt64(1) << UInt64(bit))
                        }
                        unknownBits &= unknownBits - 1
                    }
                }
                required.append(contentsOf: requiredInWord)
            }
            requiredBox.mutate { $0[worker] = required }
        }
        let requiredPrefixes = (0..<workerCount)
            .flatMap { requiredBox.value()[$0] ?? [] }
            .sorted()
        let requiredSuccessCount = samples.sampleCount - Int(
            (modelConfiguration.coverageQuantile * Double(samples.sampleCount - 1)).rounded(.down)
        )
        let cutoff = requiredPrefixes[min(requiredSuccessCount - 1, requiredPrefixes.count - 1)]
        let selectedIndexes = ranked.prefix(cutoff).map(\.0)
        guard pruneRedundant else {
            return Set(selectedIndexes.map { inventory.candidates[$0].canonicalKey })
        }

        var totals = baseline
        for index in selectedIndexes {
            addLearningGain(candidateIndex: index, samples: samples, totals: &totals)
        }
        var quantileScratch = Array(repeating: 0, count: samples.sampleCount)
        var removedIndexes = Set<Int>()
        for index in selectedIndexes.reversed() {
            removeLearningGain(candidateIndex: index, samples: samples, totals: &totals)
            if Self.coverageLowerBound(
                totals: totals,
                totalOccurrences: samples.totalOccurrences,
                quantile: modelConfiguration.coverageQuantile,
                scratch: &quantileScratch
            ) >= target {
                removedIndexes.insert(index)
            } else {
                addLearningGain(candidateIndex: index, samples: samples, totals: &totals)
            }
        }
        return Set(selectedIndexes.compactMap {
            removedIndexes.contains($0) ? nil : inventory.candidates[$0].canonicalKey
        })
    }

    private func exactCoverageSelection(
        target: Double,
        samples: PredictiveCoverageSamples,
        baseline: [Int]
    ) -> Set<String>? {
        let indexes = samples.includedIndexes
        var found: [Int]?
        func search(start: Int, remaining: Int, chosen: inout [Int], totals: [Int]) {
            guard found == nil else { return }
            if remaining == 0 {
                if Self.coverageLowerBound(
                    totals: totals,
                    totalOccurrences: samples.totalOccurrences,
                    quantile: modelConfiguration.coverageQuantile
                ) >= target {
                    found = chosen
                }
                return
            }
            guard indexes.count - start >= remaining else { return }
            for position in start...(indexes.count - remaining) {
                let index = indexes[position]
                var nextTotals = totals
                addLearningGain(candidateIndex: index, samples: samples, totals: &nextTotals)
                chosen.append(index)
                search(start: position + 1, remaining: remaining - 1, chosen: &chosen, totals: nextTotals)
                chosen.removeLast()
                if found != nil { return }
            }
        }
        for count in 1...indexes.count {
            var chosen: [Int] = []
            search(start: 0, remaining: count, chosen: &chosen, totals: baseline)
            if let found {
                return Set(found.map { inventory.candidates[$0].canonicalKey })
            }
        }
        return nil
    }

    private func baselineCoverageTotals(_ samples: PredictiveCoverageSamples) -> [Int] {
        samples.baselineTotals
    }

    private func addLearningGain(
        candidateIndex: Int,
        samples: PredictiveCoverageSamples,
        totals: inout [Int]
    ) {
        let weight = inventory.candidates[candidateIndex].occurrenceCount
        let maskOffset = candidateIndex * samples.maskWordCount
        for wordIndex in 0..<samples.maskWordCount {
            var unknownBits = ~samples.knownMaskWords[maskOffset + wordIndex]
            while unknownBits != 0 {
                let bit = unknownBits.trailingZeroBitCount
                totals[wordIndex * 64 + bit] += weight
                unknownBits &= unknownBits - 1
            }
        }
    }

    private func removeLearningGain(
        candidateIndex: Int,
        samples: PredictiveCoverageSamples,
        totals: inout [Int]
    ) {
        let weight = inventory.candidates[candidateIndex].occurrenceCount
        let maskOffset = candidateIndex * samples.maskWordCount
        for wordIndex in 0..<samples.maskWordCount {
            var unknownBits = ~samples.knownMaskWords[maskOffset + wordIndex]
            while unknownBits != 0 {
                let bit = unknownBits.trailingZeroBitCount
                totals[wordIndex * 64 + bit] -= weight
                unknownBits &= unknownBits - 1
            }
        }
    }

    private static func coverageLowerBound(
        totals: [Int],
        totalOccurrences: Int,
        quantile: Double
    ) -> Double {
        guard totalOccurrences > 0 else { return 1 }
        var scratch = Array(repeating: 0, count: totals.count)
        return coverageLowerBound(
            totals: totals,
            totalOccurrences: totalOccurrences,
            quantile: quantile,
            scratch: &scratch
        )
    }

    private static func coverageLowerBound(
        totals: [Int],
        totalOccurrences: Int,
        quantile: Double,
        scratch: inout [Int]
    ) -> Double {
        guard totalOccurrences > 0 else { return 1 }
        for index in totals.indices { scratch[index] = totals[index] }
        let target = Int((quantile * Double(scratch.count - 1)).rounded(.down))
        var lower = 0
        var upper = scratch.count - 1
        while lower < upper {
            let pivot = scratch[(lower + upper) >> 1]
            var left = lower
            var right = upper
            while left <= right {
                while scratch[left] < pivot { left += 1 }
                while scratch[right] > pivot { right -= 1 }
                if left <= right {
                    scratch.swapAt(left, right)
                    left += 1
                    right -= 1
                }
            }
            if target <= right {
                upper = right
            } else if target >= left {
                lower = left
            } else {
                break
            }
        }
        return Double(scratch[target]) / Double(totalOccurrences)
    }

    private static func maskContains(_ mask: [UInt64], _ sample: Int) -> Bool {
        mask[sample >> 6] & (UInt64(1) << UInt64(sample & 63)) != 0
    }

    private static func maskContains(
        _ samples: PredictiveCoverageSamples,
        candidateIndex: Int,
        sample: Int
    ) -> Bool {
        samples.knownMaskWords[candidateIndex * samples.maskWordCount + (sample >> 6)]
            & (UInt64(1) << UInt64(sample & 63)) != 0
    }

    private func bestAvailableQuestionReduction() -> Double {
        if let cachedBestQuestion { return cachedBestQuestion.reduction }
        if answeredQuestionCount >= 80 { return 0 }
        let remaining = answerableCandidates
        guard !remaining.isEmpty else { return 0 }
        return bestQuestion(from: shortlist(from: remaining)).reduction
    }

    private func validationCandidate(from candidates: [DocumentVocabularyCandidate]) -> (DocumentVocabularyCandidate, Bool?)? {
        let tails = candidates.compactMap { candidate -> (DocumentVocabularyCandidate, Double)? in
            guard let index = candidateIndexByKey[candidate.canonicalKey] else { return nil }
            let p = currentProbabilities[index]
            guard p <= 0.15 || p >= 0.85 else { return nil }
            return (candidate, p)
        }
        guard !tails.isEmpty else { return nil }
        let preferKnown = ((answeredQuestionCount / 5) % 2 == 0)
        let preferred = tails.filter { preferKnown ? $0.1 >= 0.85 : $0.1 <= 0.15 }
        let pool = preferred.isEmpty ? tails : preferred
        let selected = pool.sorted {
            let lhsTail = min($0.1, 1 - $0.1)
            let rhsTail = min($1.1, 1 - $1.1)
            if lhsTail != rhsTail { return lhsTail < rhsTail }
            return $0.0.canonicalKey < $1.0.canonicalKey
        }[0]
        return (selected.0, selected.1 >= 0.5)
    }

    private func shortlist(from candidates: [DocumentVocabularyCandidate]) -> [DocumentVocabularyCandidate] {
        guard candidates.count > 16 else { return candidates }
        struct Score {
            let candidate: DocumentVocabularyCandidate
            let boundary: Double
            let importance: Double
        }
        var byBoundary: [Score] = []
        var byImportance: [Score] = []
        for candidate in candidates {
            guard let index = candidateIndexByKey[candidate.canonicalKey] else { continue }
            let probability = currentProbabilities[index]
            let score = Score(
                candidate: candidate,
                boundary: abs(probability - 0.5),
                importance: Double(candidate.occurrenceCount) * min(probability, 1 - probability)
            )
            byBoundary.append(score)
            byBoundary.sort {
                if $0.boundary != $1.boundary { return $0.boundary < $1.boundary }
                return $0.candidate.canonicalKey < $1.candidate.canonicalKey
            }
            if byBoundary.count > 8 { byBoundary.removeLast() }
            byImportance.append(score)
            byImportance.sort {
                if $0.importance != $1.importance { return $0.importance > $1.importance }
                return $0.candidate.canonicalKey < $1.candidate.canonicalKey
            }
            if byImportance.count > 8 { byImportance.removeLast() }
        }
        var seen = Set<String>()
        return (byBoundary + byImportance)
            .map(\.candidate)
            .filter { seen.insert($0.canonicalKey).inserted }
    }

    private func bestQuestion(from candidates: [DocumentVocabularyCandidate]) -> (candidate: DocumentVocabularyCandidate, reduction: Double) {
        let currentLoss = loss(posterior: posterior)
        let workerCount = candidates.count >= 8 ? 4 : 1
        let resultBox = VocabularySynchronizedBox<[Int: [ScoredQuestion]]>([:])
        DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
            var local: [ScoredQuestion] = []
            var candidateOffset = worker
            while candidateOffset < candidates.count {
                let candidate = candidates[candidateOffset]
                if let index = candidateIndexByKey[candidate.canonicalKey] {
                    let pKnown = currentProbabilities[index]
                    let knownPosterior = updatedPosterior(for: candidate, known: true)
                    let unknownPosterior = updatedPosterior(for: candidate, known: false)
                    let expectedLoss = pKnown * loss(posterior: knownPosterior, excludingIndex: index)
                        + (1 - pKnown) * loss(posterior: unknownPosterior, excludingIndex: index)
                    local.append(ScoredQuestion(
                        candidate: candidate,
                        reduction: max(0.0, currentLoss - expectedLoss)
                    ))
                }
                candidateOffset += workerCount
            }
            resultBox.mutate { $0[worker] = local }
        }
        let scored = (0..<workerCount).flatMap { resultBox.value()[$0] ?? [] }
        let best = scored.sorted {
            if $0.reduction != $1.reduction { return $0.reduction > $1.reduction }
            return $0.candidate.canonicalKey < $1.candidate.canonicalKey
        }.first
        return best.map { ($0.candidate, $0.reduction) } ?? (candidates[0], 0.0)
    }

    private func loss(posterior: [Double], excludingIndex: Int? = nil) -> Double {
        inventory.candidates.enumerated().reduce(0.0) { partial, pair in
            let (index, candidate) = pair
            guard index != excludingIndex,
                  !excludedCandidateIndexes.contains(index) else { return partial }
            let p = probability(
                candidateIndex: index,
                posterior: posterior,
                epsilonKnowledge: epsilonKnowledge
            )
            let weight: Double = mode == .allUnknown ? 1 : Double(candidate.occurrenceCount)
            return partial + weight * min(p, 1 - p)
        }
    }

    private func updatedPosterior(for candidate: DocumentVocabularyCandidate, known: Bool) -> [Double] {
        guard let candidateIndex = candidateIndexByKey[candidate.canonicalKey] else { return posterior }
        var result = posterior
        for index in result.indices {
            let latentKnown = VocabularyKnowledgeModel.adjustedKnownProbability(
                baseKnownProbability: responseCurves[candidateIndex][index],
                epsilonKnowledge: epsilonKnowledge
            )
            result[index] *= VocabularyObservationModel.evidenceLikelihood(
                evidence: known ? .verifiedKnown : .reportedUnknown,
                latentKnownProbability: latentKnown,
                reliabilityScale: modelConfiguration.evidenceReliabilityScale
            )
        }
        Self.normalize(&result)
        return result
    }

    private func probability(
        candidateIndex: Int,
        posterior: [Double],
        epsilonKnowledge: Double
    ) -> Double {
        let baseProbability = zip(responseCurves[candidateIndex], posterior).reduce(0.0) { partial, pair in
            partial + pair.0 * pair.1
        }
        return VocabularyKnowledgeModel.adjustedKnownProbability(
            baseKnownProbability: baseProbability,
            epsilonKnowledge: epsilonKnowledge
        )
    }

    private func probabilities(for posterior: [Double]) -> [Double] {
        inventory.candidates.indices.map {
            probability(
                candidateIndex: $0,
                posterior: posterior,
                epsilonKnowledge: epsilonKnowledge
            )
        }
    }

    private func candidate(for canonicalKey: String) -> DocumentVocabularyCandidate? {
        candidateIndexByKey[canonicalKey].map { inventory.candidates[$0] }
    }

    private func posteriorQuantile(_ quantile: Double) -> Double {
        var cumulative = 0.0
        for (theta, weight) in zip(Self.thetaGrid, posterior) {
            cumulative += weight
            if cumulative >= quantile { return theta }
        }
        return Self.thetaGrid.last ?? 6
    }

    private func posteriorMean() -> Double {
        zip(Self.thetaGrid, posterior).reduce(0.0) { $0 + $1.0 * $1.1 }
    }

    private static func baseItemProbability(
        theta: Double,
        difficultyPrior: VocabularyItemDifficultyPrior
    ) -> Double {
        guard difficultyPrior.standardDeviation > 0 else {
            return VocabularyKnowledgeModel.baseKnownProbability(
                theta: theta,
                difficulty: difficultyPrior.mean
            )
        }
        let scale = sqrt(2) * difficultyPrior.standardDeviation
        return gaussianQuadrature.reduce(0.0) { partial, point in
            partial + point.weight * VocabularyKnowledgeModel.baseKnownProbability(
                theta: theta,
                difficulty: difficultyPrior.mean + scale * point.node
            )
        }
    }

    private static func inventorySeed(_ inventory: DocumentVocabularyInventory) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        func mix(_ byte: UInt8) {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        for byte in inventory.languageCode.utf8 { mix(byte) }
        for candidate in inventory.candidates {
            for byte in candidate.canonicalKey.utf8 { mix(byte) }
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
        withUnsafeBytes(of: UInt64(VocabularyPreparationSession.currentAlgorithmVersion).littleEndian) { bytes in
            for byte in bytes { mix(byte) }
        }
        return hash
    }

    private static func nextRandomUnit(state: inout UInt64) -> Double {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let value = state &* 0x2545_F491_4F6C_DD1D
        return Double(value >> 11) * 0x1.0p-53
    }

    private mutating func rebuildAnsweredProbabilities() {
        answeredProbabilities.removeAll(keepingCapacity: true)
        for answer in answers where answer.evidence != .excluded {
            guard let candidateIndex = candidateIndexByKey[answer.canonicalKey] else { continue }
            var leaveOneOut = posterior
            for thetaIndex in leaveOneOut.indices {
                let latentKnown = VocabularyKnowledgeModel.adjustedKnownProbability(
                    baseKnownProbability: responseCurves[candidateIndex][thetaIndex],
                    epsilonKnowledge: epsilonKnowledge
                )
                let likelihood = VocabularyObservationModel.evidenceLikelihood(
                    evidence: answer.evidence,
                    latentKnownProbability: latentKnown,
                    reliabilityScale: modelConfiguration.evidenceReliabilityScale
                )
                leaveOneOut[thetaIndex] /= max(likelihood, Double.leastNormalMagnitude)
            }
            Self.normalize(&leaveOneOut)
            let prior = probability(
                candidateIndex: candidateIndex,
                posterior: leaveOneOut,
                epsilonKnowledge: epsilonKnowledge
            )
            answeredProbabilities[answer.canonicalKey] = VocabularyObservationModel.posteriorKnownProbability(
                prior: prior,
                evidence: answer.evidence,
                reliabilityScale: modelConfiguration.evidenceReliabilityScale
            )
        }
    }

    private static func contradictionAmount(
        evidence: VocabularyKnowledgeEvidence,
        predictedKnown: Bool
    ) -> Double {
        guard evidence != .excluded else { return 0 }
        if evidence == .unsure { return 0.5 }
        return evidence.supportsKnown == predictedKnown ? 0 : 1
    }

    private static func normalPrior() -> [Double] {
        var values = thetaGrid.map { exp(-0.5 * pow($0 / 2.5, 2)) }
        normalize(&values)
        return values
    }

    private static func normalize(_ values: inout [Double]) {
        let total = values.reduce(0, +)
        guard total.isFinite, total > 0 else {
            values = normalPrior()
            return
        }
        for index in values.indices { values[index] /= total }
    }

    private static func difficultyOrder(_ lhs: DocumentVocabularyCandidate, _ rhs: DocumentVocabularyCandidate) -> Bool {
        if lhs.difficulty != rhs.difficulty { return lhs.difficulty < rhs.difficulty }
        return lhs.canonicalKey < rhs.canonicalKey
    }
}
