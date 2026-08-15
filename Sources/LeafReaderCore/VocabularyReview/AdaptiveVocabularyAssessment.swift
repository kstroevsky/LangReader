import Foundation

private let vocabularyCoverageOneSided95Z = 1.644_853_626_951_47

package enum VocabularyAssessmentMode: Codable, Equatable, Sendable {
    case allUnknown
    case targetCoverage(Double)

    package var targetCoverage: Double? {
        guard case let .targetCoverage(value) = self else { return nil }
        return min(max(value, 0), 1)
    }
}

package enum VocabularyAssessmentOutcome: String, Codable, Equatable, Sendable {
    case known
    case unknown
    case excluded
}

package struct DocumentVocabularyCandidate: Codable, Equatable, Identifiable, Sendable {
    package var id: String { canonicalKey }
    package let canonicalKey: String
    package let displayLemma: String
    package let observedForms: [VocabularyDocumentObservedForm]
    package let occurrenceCount: Int
    package let representativeRange: VocabularyDocumentSourceRange
    package let generalFrequencyRank: Int?
    package let difficulty: Double

    package init(
        canonicalKey: String,
        displayLemma: String,
        observedForms: [VocabularyDocumentObservedForm],
        occurrenceCount: Int,
        representativeRange: VocabularyDocumentSourceRange,
        generalFrequencyRank: Int?,
        difficulty: Double
    ) {
        self.canonicalKey = canonicalKey
        self.displayLemma = displayLemma
        self.observedForms = observedForms
        self.occurrenceCount = occurrenceCount
        self.representativeRange = representativeRange
        self.generalFrequencyRank = generalFrequencyRank
        self.difficulty = difficulty
    }
}

package struct DocumentVocabularyInventory: Codable, Equatable, Sendable {
    package let languageCode: String
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
                displayLemma: summary.displayLemma,
                observedForms: summary.observedForms,
                occurrenceCount: summary.occurrenceCount,
                representativeRange: summary.representativeRange,
                generalFrequencyRank: resolvedRank,
                difficulty: Self.difficulty(forRank: resolvedRank, maximumRank: maximumFrequencyRank)
            )
        }.sorted(by: Self.inventoryOrder)
        self.languageCode = languageCode
        excludedCount = summaries.count - valid.count
    }

    package init(languageCode: String, candidates: [DocumentVocabularyCandidate], excludedCount: Int = 0) {
        self.languageCode = languageCode
        self.candidates = candidates.sorted(by: Self.inventoryOrder)
        self.excludedCount = excludedCount
    }

    package static func difficulty(forRank rank: Int?, maximumRank: Int) -> Double {
        guard let rank, rank > 0, maximumRank > 0 else { return 4 }
        let percentile = min(max(Double(rank) / Double(maximumRank), 0.0001), 0.9999)
        return min(max(log(percentile / (1 - percentile)), -4), 4)
    }

    private static func isAssessable(_ summary: VocabularyDocumentLemmaSummary) -> Bool {
        guard !summary.isConfidentName,
              !summary.canonicalKey.isEmpty,
              summary.canonicalKey.count <= 64 else { return false }
        let scalars = summary.canonicalKey.unicodeScalars
        guard scalars.contains(where: CharacterSet.letters.contains) else { return false }
        guard scalars.allSatisfy({
            CharacterSet.letters.contains($0)
                || CharacterSet.nonBaseCharacters.contains($0)
                || $0 == "'" || $0 == "’" || $0 == "-"
        }) else { return false }
        let key = summary.canonicalKey
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

package struct VocabularyAssessmentAnswer: Codable, Equatable, Sendable {
    package let canonicalKey: String
    package let outcome: VocabularyAssessmentOutcome
    package let wasValidation: Bool
    package let predictedKnown: Bool?

    package init(
        canonicalKey: String,
        outcome: VocabularyAssessmentOutcome,
        wasValidation: Bool = false,
        predictedKnown: Bool? = nil
    ) {
        self.canonicalKey = canonicalKey
        self.outcome = outcome
        self.wasValidation = wasValidation
        self.predictedKnown = predictedKnown
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
    package static let currentAlgorithmVersion = 2

    package var mode: VocabularyAssessmentMode
    package var invitationState: VocabularyPreparationInvitationState
    package var answers: [VocabularyAssessmentAnswer]
    package var finalSelection: Set<String>
    package var algorithmVersion: Int

    package init(
        mode: VocabularyAssessmentMode = .allUnknown,
        invitationState: VocabularyPreparationInvitationState = .notOffered,
        answers: [VocabularyAssessmentAnswer] = [],
        finalSelection: Set<String> = [],
        algorithmVersion: Int = currentAlgorithmVersion
    ) {
        self.mode = mode
        self.invitationState = invitationState
        self.answers = answers
        self.finalSelection = finalSelection
        self.algorithmVersion = algorithmVersion
    }
}

package enum VocabularyAssessmentClassification: String, Codable, Equatable, Sendable {
    case confirmedKnown
    case confirmedUnknown
    case probablyKnown
    case uncertain
    case probablyUnknown
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
}

package struct VocabularyAssessmentResult: Codable, Equatable, Sendable {
    package let items: [VocabularyAssessmentResultItem]
    package let answeredQuestionCount: Int
    package let errorFloor: Double
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
                isSelected: selected
            )
        }
        let conservativeCoverage = Self.coverageLowerBound(
            items: updatedItems,
            theta: diagnostics.thetaLowerBound,
            epsilon: errorFloor
        )
        return VocabularyAssessmentResult(
            items: updatedItems,
            answeredQuestionCount: answeredQuestionCount,
            errorFloor: errorFloor,
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
        theta: Double,
        epsilon: Double
    ) -> Double {
        let included = items.filter { $0.classification != .excluded }
        let total = Double(included.reduce(0) { $0 + $1.candidate.occurrenceCount })
        guard total > 0 else { return 1 }
        var variance = 0.0
        let known = included.reduce(0.0) { partial, item in
            let probability: Double
            if item.isSelected || item.classification == .confirmedKnown {
                probability = 1
            } else if item.classification == .confirmedUnknown {
                probability = 0
            } else {
                probability = epsilon
                    + (1 - 2 * epsilon) / (1 + exp(-(theta - item.candidate.difficulty)))
            }
            let weight = Double(item.candidate.occurrenceCount)
            variance += weight * weight * probability * (1 - probability)
            return partial + weight * probability
        }
        return min(1, max(0, (known - vocabularyCoverageOneSided95Z * sqrt(variance)) / total))
    }
}

package struct AdaptiveVocabularyAssessment: Sendable {
    private struct PendingQuestion: Sendable {
        let key: String
        let validationPrediction: Bool?
    }

    private struct BestQuestionCache: Sendable {
        let key: String
        let reduction: Double
    }

    private static let thetaGrid: [Double] = stride(from: -6.0, through: 6.0001, by: 0.1).map { $0 }
    private let inventory: DocumentVocabularyInventory
    private let candidateIndexByKey: [String: Int]
    private let responseCurves: [[Double]]
    private let difficultyOrderedIndexes: [Int]
    private(set) package var mode: VocabularyAssessmentMode
    private(set) package var answers: [VocabularyAssessmentAnswer]
    private(set) package var errorFloor: Double = 0.05
    private var posterior: [Double]
    private var answerByKey: [String: VocabularyAssessmentAnswer]
    private var answeredCandidateIndexes: Set<Int>
    private var currentProbabilities: [Double]
    private var pendingQuestion: PendingQuestion?
    private var skippedQuestionKeys = Set<String>()
    private var lowValueStreak = 0
    private var stableCoverageDeckStreak = 0
    private var previousCoverageDeck: Set<String>?
    private var suppressStoppingUpdateOnce = false
    private var cachedBestQuestion: BestQuestionCache?

    package init(
        inventory: DocumentVocabularyInventory,
        mode: VocabularyAssessmentMode,
        restoredAnswers: [VocabularyAssessmentAnswer] = []
    ) {
        self.inventory = inventory
        self.mode = mode
        candidateIndexByKey = Dictionary(uniqueKeysWithValues: inventory.candidates.enumerated().map {
            ($0.element.canonicalKey, $0.offset)
        })
        responseCurves = inventory.candidates.map { candidate in
            Self.thetaGrid.map { theta in Self.baseItemProbability(theta: theta, difficulty: candidate.difficulty) }
        }
        difficultyOrderedIndexes = inventory.candidates.indices.sorted {
            Self.difficultyOrder(inventory.candidates[$0], inventory.candidates[$1])
        }
        answers = []
        posterior = Self.normalPrior()
        answerByKey = [:]
        answeredCandidateIndexes = []
        currentProbabilities = []
        currentProbabilities = probabilities(for: posterior)
        for answer in restoredAnswers where candidateIndexByKey[answer.canonicalKey] != nil {
            apply(answer)
        }
        refreshStoppingState()
    }

    package var answeredQuestionCount: Int {
        answers.lazy.filter { $0.outcome != .excluded }.count
    }

    package var isFinished: Bool {
        if answeredQuestionCount >= 80 { return true }
        let remaining = answerableCandidates
        let minimumAnswerCount = min(20, answeredQuestionCount + remaining.count)
        guard answeredQuestionCount >= minimumAnswerCount else { return false }
        if remaining.isEmpty { return true }
        switch mode {
        case .allUnknown:
            return lowValueStreak >= 3
        case .targetCoverage:
            return stableCoverageDeckStreak >= 3
                && coverageLowerBound(selection: proposedSelection()) >= (mode.targetCoverage ?? 0.98)
        }
    }

    package mutating func setMode(_ mode: VocabularyAssessmentMode) {
        self.mode = mode
        lowValueStreak = 0
        stableCoverageDeckStreak = 0
        previousCoverageDeck = nil
        cachedBestQuestion = nil
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
        let selected: (DocumentVocabularyCandidate, Bool?)
        if questionNumber <= 8 {
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
            selected = (nearest, nil)
        } else if questionNumber > 10, questionNumber.isMultiple(of: 5), let validation = validationCandidate(from: remaining) {
            selected = validation
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
            selected = (adaptive, nil)
        }
        pendingQuestion = PendingQuestion(key: selected.0.canonicalKey, validationPrediction: selected.1)
        return selected.0
    }

    package mutating func record(_ outcome: VocabularyAssessmentOutcome, for canonicalKey: String) {
        guard candidateIndexByKey[canonicalKey] != nil, answerByKey[canonicalKey] == nil else { return }
        cachedBestQuestion = nil
        let pending = pendingQuestion?.key == canonicalKey ? pendingQuestion : nil
        let answer = VocabularyAssessmentAnswer(
            canonicalKey: canonicalKey,
            outcome: outcome,
            wasValidation: pending?.validationPrediction != nil,
            predictedKnown: pending?.validationPrediction
        )
        apply(answer)
        pendingQuestion = nil
        refreshStoppingState()
    }

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
            switch answer.outcome {
            case .known: return 1
            case .unknown: return 0
            case .excluded: return nil
            }
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
        let proposed = proposedSelection()
        let selection = selectionOverride ?? proposed
        var totalOccurrences = 0.0
        var expectedKnownOccurrences = 0.0
        let items = inventory.candidates.map { candidate -> VocabularyAssessmentResultItem in
            let answer = answerByKey[candidate.canonicalKey]
            let probability = knownProbability(for: candidate.canonicalKey) ?? 0
            let classification: VocabularyAssessmentClassification
            switch answer?.outcome {
            case .known: classification = .confirmedKnown
            case .unknown: classification = .confirmedUnknown
            case .excluded: classification = .excluded
            case nil:
                if probability < 0.35 { classification = .probablyUnknown }
                else if probability <= 0.65 { classification = .uncertain }
                else { classification = .probablyKnown }
            }
            if classification != .excluded {
                let weight = Double(candidate.occurrenceCount)
                totalOccurrences += weight
                expectedKnownOccurrences += weight * (selection.contains(candidate.canonicalKey) ? 1 : probability)
            }
            return VocabularyAssessmentResultItem(
                candidate: candidate,
                knownProbability: probability,
                classification: classification,
                isSelected: classification != .excluded && selection.contains(candidate.canonicalKey)
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
            conservativeCoverageLowerBound: coverageLowerBound(selection: selection),
            skippedQuestionCount: skippedQuestionKeys.count,
            bestExpectedLossReduction: bestReduction,
            stopReason: stopReason,
            reachedQuestionLimit: reachedQuestionLimit
        )
        return VocabularyAssessmentResult(
            items: items,
            answeredQuestionCount: answeredQuestionCount,
            errorFloor: errorFloor,
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
        let minimumAnswerCount = min(20, answeredQuestionCount + remaining.count)
        guard answeredQuestionCount >= minimumAnswerCount else { return nil }
        if remaining.isEmpty { return .exhaustedCandidates }
        switch mode {
        case .allUnknown:
            return lowValueStreak >= 3 ? .lowExpectedValue : nil
        case .targetCoverage:
            return stableCoverageDeckStreak >= 3
                && coverageLowerBound(selection: proposedSelection()) >= (mode.targetCoverage ?? 0.98)
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
        }
        guard answer.outcome != .excluded,
              candidateIndexByKey[answer.canonicalKey] != nil else { return }

        if let predictedKnown = answer.predictedKnown {
            let contradicted = (predictedKnown && answer.outcome == .unknown)
                || (!predictedKnown && answer.outcome == .known)
            let validations = answers.filter { $0.predictedKnown != nil && $0.outcome != .excluded }
            let contradictions = validations.filter {
                ($0.predictedKnown == true && $0.outcome == .unknown)
                    || ($0.predictedKnown == false && $0.outcome == .known)
            }.count
            let smoothedRate = Double(contradictions + 1) / Double(validations.count + 20)
            errorFloor = min(0.25, max(0.05, smoothedRate))
            if contradicted && answeredQuestionCount >= 20 {
                lowValueStreak = 0
                stableCoverageDeckStreak = 0
                suppressStoppingUpdateOnce = true
            }
        }

        rebuildPosterior()
    }

    private mutating func rebuildPosterior() {
        posterior = Self.normalPrior()
        for answer in answers where answer.outcome != .excluded {
            guard let candidateIndex = candidateIndexByKey[answer.canonicalKey] else { continue }
            let expectedKnown = answer.outcome == .known
            for index in posterior.indices {
                let p = Self.adjustedProbability(responseCurves[candidateIndex][index], epsilon: errorFloor)
                posterior[index] *= expectedKnown ? p : (1 - p)
            }
            Self.normalize(&posterior)
        }
        currentProbabilities = probabilities(for: posterior)
    }

    private mutating func refreshStoppingState() {
        cachedBestQuestion = nil
        if suppressStoppingUpdateOnce {
            suppressStoppingUpdateOnce = false
            return
        }
        let remaining = answerableCandidates
        let minimumAnswerCount = min(20, answeredQuestionCount + remaining.count)
        guard answeredQuestionCount < 80,
              answeredQuestionCount >= minimumAnswerCount,
              !remaining.isEmpty else { return }
        switch mode {
        case .allUnknown:
            let best = bestQuestion(from: shortlist(from: remaining))
            cachedBestQuestion = BestQuestionCache(key: best.candidate.canonicalKey, reduction: best.reduction)
            lowValueStreak = best.reduction < 0.25 ? lowValueStreak + 1 : 0
        case .targetCoverage:
            let deck = proposedSelection()
            stableCoverageDeckStreak = previousCoverageDeck == deck ? stableCoverageDeckStreak + 1 : 0
            previousCoverageDeck = deck
        }
    }

    private func proposedSelection() -> Set<String> {
        let eligible = inventory.candidates.filter { candidate in
            answerByKey[candidate.canonicalKey]?.outcome != .excluded
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
            let lowerTheta = posteriorQuantile(0.05)
            let conservativeProbabilities = Dictionary(uniqueKeysWithValues: eligible.map { candidate in
                let probability: Double
                switch answerByKey[candidate.canonicalKey]?.outcome {
                case .known:
                    probability = 1
                case .unknown:
                    probability = 0
                case .excluded:
                    probability = 0
                case nil:
                    probability = Self.itemProbability(
                        theta: lowerTheta,
                        difficulty: candidate.difficulty,
                        epsilon: errorFloor
                    )
                }
                return (candidate.canonicalKey, probability)
            })
            let total = Double(eligible.reduce(0) { $0 + $1.occurrenceCount })
            guard total > 0 else { return [] }
            var expectedKnown = eligible.reduce(0.0) { partial, candidate in
                partial + Double(candidate.occurrenceCount)
                    * (conservativeProbabilities[candidate.canonicalKey] ?? 0)
            }
            var variance = eligible.reduce(0.0) { partial, candidate in
                let weight = Double(candidate.occurrenceCount)
                let probability = conservativeProbabilities[candidate.canonicalKey] ?? 0
                return partial + weight * weight * probability * (1 - probability)
            }
            var selection = Set<String>()
            let ranked = eligible.sorted {
                let lhsProbability = conservativeProbabilities[$0.canonicalKey] ?? 0
                let rhsProbability = conservativeProbabilities[$1.canonicalKey] ?? 0
                let lhsWeight = Double($0.occurrenceCount)
                let rhsWeight = Double($1.occurrenceCount)
                let lhsGain = lhsWeight * (1 - lhsProbability)
                    + vocabularyCoverageOneSided95Z * lhsWeight * sqrt(lhsProbability * (1 - lhsProbability))
                let rhsGain = rhsWeight * (1 - rhsProbability)
                    + vocabularyCoverageOneSided95Z * rhsWeight * sqrt(rhsProbability * (1 - rhsProbability))
                if lhsGain != rhsGain { return lhsGain > rhsGain }
                return $0.canonicalKey < $1.canonicalKey
            }
            for candidate in ranked where (
                expectedKnown - vocabularyCoverageOneSided95Z * sqrt(max(0, variance))
            ) / total < target {
                let probability = conservativeProbabilities[candidate.canonicalKey] ?? 0
                let weight = Double(candidate.occurrenceCount)
                expectedKnown += weight * (1 - probability)
                variance -= weight * weight * probability * (1 - probability)
                selection.insert(candidate.canonicalKey)
            }
            return selection
        }
    }

    private func coverageLowerBound(selection: Set<String>) -> Double {
        let lowerTheta = posteriorQuantile(0.05)
        let included = inventory.candidates.filter { knownProbability(for: $0.canonicalKey) != nil }
        let total = Double(included.reduce(0) { $0 + $1.occurrenceCount })
        guard total > 0 else { return 1 }
        var variance = 0.0
        let known = included.reduce(0.0) { partial, candidate in
            let answer = answerByKey[candidate.canonicalKey]
            let p: Double
            if selection.contains(candidate.canonicalKey) || answer?.outcome == .known {
                p = 1
            } else if answer?.outcome == .unknown {
                p = 0
            } else {
                p = Self.itemProbability(theta: lowerTheta, difficulty: candidate.difficulty, epsilon: errorFloor)
            }
            let weight = Double(candidate.occurrenceCount)
            variance += weight * weight * p * (1 - p)
            return partial + weight * p
        }
        return min(1, max(0, (known - vocabularyCoverageOneSided95Z * sqrt(variance)) / total))
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
        return candidates.map { candidate in
            guard let index = candidateIndexByKey[candidate.canonicalKey] else { return (candidate, 0.0) }
            let pKnown = currentProbabilities[index]
            let knownPosterior = updatedPosterior(for: candidate, known: true)
            let unknownPosterior = updatedPosterior(for: candidate, known: false)
            let expectedLoss = pKnown * loss(posterior: knownPosterior, excluding: candidate.canonicalKey)
                + (1 - pKnown) * loss(posterior: unknownPosterior, excluding: candidate.canonicalKey)
            return (candidate, max(0.0, currentLoss - expectedLoss))
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.canonicalKey < $1.0.canonicalKey
        }.first ?? (candidates[0], 0.0)
    }

    private func loss(posterior: [Double], excluding excludedKey: String? = nil) -> Double {
        inventory.candidates.enumerated().reduce(0.0) { partial, pair in
            let (index, candidate) = pair
            guard candidate.canonicalKey != excludedKey,
                  !answeredCandidateIndexes.contains(index) else { return partial }
            let p = probability(candidateIndex: index, posterior: posterior, epsilon: errorFloor)
            let weight: Double = mode == .allUnknown ? 1 : Double(candidate.occurrenceCount)
            return partial + weight * min(p, 1 - p)
        }
    }

    private func updatedPosterior(for candidate: DocumentVocabularyCandidate, known: Bool) -> [Double] {
        guard let candidateIndex = candidateIndexByKey[candidate.canonicalKey] else { return posterior }
        var result = posterior
        for index in result.indices {
            let p = Self.adjustedProbability(responseCurves[candidateIndex][index], epsilon: errorFloor)
            result[index] *= known ? p : (1 - p)
        }
        Self.normalize(&result)
        return result
    }

    private func probability(candidateIndex: Int, posterior: [Double], epsilon: Double) -> Double {
        let baseProbability = zip(responseCurves[candidateIndex], posterior).reduce(0.0) { partial, pair in
            partial + pair.0 * pair.1
        }
        return Self.adjustedProbability(baseProbability, epsilon: epsilon)
    }

    private func probabilities(for posterior: [Double]) -> [Double] {
        inventory.candidates.indices.map {
            probability(candidateIndex: $0, posterior: posterior, epsilon: errorFloor)
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

    private static func itemProbability(theta: Double, difficulty: Double, epsilon: Double) -> Double {
        adjustedProbability(baseItemProbability(theta: theta, difficulty: difficulty), epsilon: epsilon)
    }

    private static func baseItemProbability(theta: Double, difficulty: Double) -> Double {
        1 / (1 + exp(-(theta - difficulty)))
    }

    private static func adjustedProbability(_ baseProbability: Double, epsilon: Double) -> Double {
        epsilon + (1 - 2 * epsilon) * baseProbability
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
