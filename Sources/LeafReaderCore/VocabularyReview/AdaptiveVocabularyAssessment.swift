import Foundation

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
        return scalars.allSatisfy {
            CharacterSet.letters.contains($0)
                || CharacterSet.nonBaseCharacters.contains($0)
                || $0 == "'" || $0 == "’" || $0 == "-"
        }
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
    package static let currentAlgorithmVersion = 1

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
        return VocabularyAssessmentResult(
            items: updatedItems,
            answeredQuestionCount: answeredQuestionCount,
            errorFloor: errorFloor,
            expectedCoverageAfterSelection: totalOccurrences > 0 ? expectedKnownOccurrences / totalOccurrences : 1,
            residualUncertainty: residualUncertainty,
            reachedQuestionLimit: reachedQuestionLimit
        )
    }
}

package struct AdaptiveVocabularyAssessment: Sendable {
    private struct PendingQuestion: Sendable {
        let key: String
        let validationPrediction: Bool?
    }

    private static let thetaGrid: [Double] = stride(from: -6.0, through: 6.0001, by: 0.1).map { $0 }
    private let inventory: DocumentVocabularyInventory
    private(set) package var mode: VocabularyAssessmentMode
    private(set) package var answers: [VocabularyAssessmentAnswer]
    private(set) package var errorFloor: Double = 0.05
    private var posterior: [Double]
    private var pendingQuestion: PendingQuestion?
    private var skippedQuestionKeys = Set<String>()
    private var lowValueStreak = 0
    private var stableCoverageDeckStreak = 0
    private var previousCoverageDeck = Set<String>()
    private var contradictionAfterMinimum = false

    package init(
        inventory: DocumentVocabularyInventory,
        mode: VocabularyAssessmentMode,
        restoredAnswers: [VocabularyAssessmentAnswer] = []
    ) {
        self.inventory = inventory
        self.mode = mode
        answers = []
        posterior = Self.normalPrior()
        for answer in restoredAnswers where inventory.candidates.contains(where: { $0.canonicalKey == answer.canonicalKey }) {
            apply(answer)
        }
        refreshStoppingState()
    }

    package var answeredQuestionCount: Int {
        answers.lazy.filter { $0.outcome != .excluded }.count
    }

    package var isFinished: Bool {
        if answeredQuestionCount >= min(80, inventory.candidates.count) { return true }
        guard answeredQuestionCount >= min(20, inventory.candidates.count), !contradictionAfterMinimum else { return false }
        switch mode {
        case .allUnknown:
            return lowValueStreak >= 3
        case .targetCoverage:
            return stableCoverageDeckStreak >= 3 && coverageLowerBound() >= (mode.targetCoverage ?? 0.98)
        }
    }

    package mutating func setMode(_ mode: VocabularyAssessmentMode) {
        self.mode = mode
        lowValueStreak = 0
        stableCoverageDeckStreak = 0
        previousCoverageDeck = []
        refreshStoppingState()
    }

    package mutating func nextQuestion() -> DocumentVocabularyCandidate? {
        if let pendingQuestion {
            return inventory.candidates.first { $0.canonicalKey == pendingQuestion.key }
        }
        guard !isFinished else { return nil }
        let remaining = unaskedCandidates.filter { !skippedQuestionKeys.contains($0.canonicalKey) }
        guard !remaining.isEmpty else { return nil }

        let questionNumber = answeredQuestionCount + 1
        let selected: (DocumentVocabularyCandidate, Bool?)
        if questionNumber <= 8 {
            let fraction = (Double(questionNumber) - 0.5) / 8.0
            let allOrdered = inventory.candidates.sorted(by: Self.difficultyOrder)
            let index = min(allOrdered.count - 1, max(0, Int((fraction * Double(allOrdered.count)).rounded(.down))))
            let targetDifficulty = allOrdered[index].difficulty
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
            selected = (bestQuestion(from: shortlist(from: remaining)).candidate, nil)
        }
        pendingQuestion = PendingQuestion(key: selected.0.canonicalKey, validationPrediction: selected.1)
        return selected.0
    }

    package mutating func record(_ outcome: VocabularyAssessmentOutcome, for canonicalKey: String) {
        guard inventory.candidates.contains(where: { $0.canonicalKey == canonicalKey }),
              !answers.contains(where: { $0.canonicalKey == canonicalKey }) else { return }
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
    }

    package func knownProbability(for canonicalKey: String) -> Double? {
        guard let candidate = inventory.candidates.first(where: { $0.canonicalKey == canonicalKey }) else { return nil }
        if let answer = answers.first(where: { $0.canonicalKey == canonicalKey }) {
            switch answer.outcome {
            case .known: return 1
            case .unknown: return 0
            case .excluded: return nil
            }
        }
        return probability(candidate, posterior: posterior, epsilon: errorFloor)
    }

    package func result(selectionOverride: Set<String>? = nil) -> VocabularyAssessmentResult {
        let proposed = proposedSelection()
        let selection = selectionOverride ?? proposed
        var totalOccurrences = 0.0
        var expectedKnownOccurrences = 0.0
        let items = inventory.candidates.map { candidate -> VocabularyAssessmentResultItem in
            let answer = answers.first { $0.canonicalKey == candidate.canonicalKey }
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
                isSelected: selection.contains(candidate.canonicalKey)
            )
        }
        let uncertainty = items.reduce(0.0) { partial, item in
            guard item.classification != .excluded else { return partial }
            return partial + min(item.knownProbability, 1 - item.knownProbability)
        }
        return VocabularyAssessmentResult(
            items: items,
            answeredQuestionCount: answeredQuestionCount,
            errorFloor: errorFloor,
            expectedCoverageAfterSelection: totalOccurrences > 0 ? expectedKnownOccurrences / totalOccurrences : 1,
            residualUncertainty: uncertainty,
            reachedQuestionLimit: answeredQuestionCount >= min(80, inventory.candidates.count)
        )
    }

    private var unaskedCandidates: [DocumentVocabularyCandidate] {
        let answered = Set(answers.map(\.canonicalKey))
        return inventory.candidates.filter { !answered.contains($0.canonicalKey) }
    }

    private mutating func apply(_ answer: VocabularyAssessmentAnswer) {
        answers.append(answer)
        guard answer.outcome != .excluded,
              let candidate = inventory.candidates.first(where: { $0.canonicalKey == answer.canonicalKey }) else { return }

        if let predictedKnown = answer.predictedKnown {
            let contradicted = (predictedKnown && answer.outcome == .unknown)
                || (!predictedKnown && answer.outcome == .known)
            let validations = answers.filter { $0.predictedKnown != nil && $0.outcome != .excluded }
            let contradictions = validations.filter {
                ($0.predictedKnown == true && $0.outcome == .unknown)
                    || ($0.predictedKnown == false && $0.outcome == .known)
            }.count
            let smoothedRate = Double(contradictions) / Double(validations.count + 4)
            errorFloor = min(0.25, max(0.05, smoothedRate))
            if contradicted && answeredQuestionCount >= 20 {
                contradictionAfterMinimum = true
                lowValueStreak = 0
                stableCoverageDeckStreak = 0
            }
        } else if contradictionAfterMinimum {
            contradictionAfterMinimum = false
        }

        _ = candidate
        rebuildPosterior()
    }

    private mutating func rebuildPosterior() {
        posterior = Self.normalPrior()
        for answer in answers where answer.outcome != .excluded {
            guard let candidate = inventory.candidates.first(where: { $0.canonicalKey == answer.canonicalKey }) else { continue }
            let expectedKnown = answer.outcome == .known
            for index in posterior.indices {
                let p = Self.itemProbability(
                    theta: Self.thetaGrid[index],
                    difficulty: candidate.difficulty,
                    epsilon: errorFloor
                )
                posterior[index] *= expectedKnown ? p : (1 - p)
            }
            Self.normalize(&posterior)
        }
    }

    private mutating func refreshStoppingState() {
        guard answeredQuestionCount >= min(20, inventory.candidates.count), !unaskedCandidates.isEmpty else { return }
        switch mode {
        case .allUnknown:
            let reduction = bestQuestion(from: shortlist(from: unaskedCandidates)).reduction
            lowValueStreak = reduction < 0.25 ? lowValueStreak + 1 : 0
        case .targetCoverage:
            let deck = proposedSelection()
            stableCoverageDeckStreak = deck == previousCoverageDeck ? stableCoverageDeckStreak + 1 : 0
            previousCoverageDeck = deck
        }
    }

    private func proposedSelection() -> Set<String> {
        let eligible = inventory.candidates.filter { candidate in
            answers.first(where: { $0.canonicalKey == candidate.canonicalKey })?.outcome != .excluded
        }
        switch mode {
        case .allUnknown:
            return Set(eligible.compactMap { candidate -> String? in
                guard let probability = knownProbability(for: candidate.canonicalKey) else { return nil }
                return probability < 0.5 ? candidate.canonicalKey : nil
            })
        case let .targetCoverage(target):
            let total = Double(eligible.reduce(0) { $0 + $1.occurrenceCount })
            guard total > 0 else { return [] }
            var expectedKnown = eligible.reduce(0.0) { partial, candidate in
                partial + Double(candidate.occurrenceCount) * (knownProbability(for: candidate.canonicalKey) ?? 0)
            }
            var selection = Set<String>()
            let ranked = eligible.sorted {
                let lhsGain = Double($0.occurrenceCount) * (1 - (knownProbability(for: $0.canonicalKey) ?? 0))
                let rhsGain = Double($1.occurrenceCount) * (1 - (knownProbability(for: $1.canonicalKey) ?? 0))
                if lhsGain != rhsGain { return lhsGain > rhsGain }
                return $0.canonicalKey < $1.canonicalKey
            }
            for candidate in ranked where expectedKnown / total < target {
                let probability = knownProbability(for: candidate.canonicalKey) ?? 0
                expectedKnown += Double(candidate.occurrenceCount) * (1 - probability)
                selection.insert(candidate.canonicalKey)
            }
            return selection
        }
    }

    private func coverageLowerBound() -> Double {
        guard let target = mode.targetCoverage else { return 0 }
        let deck = proposedSelection()
        let lowerTheta = posteriorQuantile(0.05)
        let included = inventory.candidates.filter { knownProbability(for: $0.canonicalKey) != nil }
        let total = Double(included.reduce(0) { $0 + $1.occurrenceCount })
        guard total > 0 else { return target }
        let known = included.reduce(0.0) { partial, candidate in
            let p = deck.contains(candidate.canonicalKey)
                ? 1
                : Self.itemProbability(theta: lowerTheta, difficulty: candidate.difficulty, epsilon: errorFloor)
            return partial + Double(candidate.occurrenceCount) * p
        }
        return known / total
    }

    private func validationCandidate(from candidates: [DocumentVocabularyCandidate]) -> (DocumentVocabularyCandidate, Bool?)? {
        let tails = candidates.compactMap { candidate -> (DocumentVocabularyCandidate, Double)? in
            let p = probability(candidate, posterior: posterior, epsilon: errorFloor)
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
        let byBoundary = candidates.sorted {
            abs(probability($0, posterior: posterior, epsilon: errorFloor) - 0.5)
                < abs(probability($1, posterior: posterior, epsilon: errorFloor) - 0.5)
        }.prefix(8)
        let byImportance = candidates.sorted {
            let lhs = Double($0.occurrenceCount) * min(probability($0, posterior: posterior, epsilon: errorFloor), 1 - probability($0, posterior: posterior, epsilon: errorFloor))
            let rhs = Double($1.occurrenceCount) * min(probability($1, posterior: posterior, epsilon: errorFloor), 1 - probability($1, posterior: posterior, epsilon: errorFloor))
            if lhs != rhs { return lhs > rhs }
            return $0.canonicalKey < $1.canonicalKey
        }.prefix(8)
        var seen = Set<String>()
        return (Array(byBoundary) + Array(byImportance)).filter { seen.insert($0.canonicalKey).inserted }
    }

    private func bestQuestion(from candidates: [DocumentVocabularyCandidate]) -> (candidate: DocumentVocabularyCandidate, reduction: Double) {
        let currentLoss = loss(posterior: posterior)
        return candidates.map { candidate in
            let pKnown = probability(candidate, posterior: posterior, epsilon: errorFloor)
            let knownPosterior = updatedPosterior(for: candidate, known: true)
            let unknownPosterior = updatedPosterior(for: candidate, known: false)
            let expectedLoss = pKnown * loss(posterior: knownPosterior, excluding: candidate.canonicalKey)
                + (1 - pKnown) * loss(posterior: unknownPosterior, excluding: candidate.canonicalKey)
            return (candidate, max(0, currentLoss - expectedLoss))
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.canonicalKey < $1.0.canonicalKey
        }.first ?? (candidates[0], 0)
    }

    private func loss(posterior: [Double], excluding excludedKey: String? = nil) -> Double {
        inventory.candidates.reduce(0.0) { partial, candidate in
            guard candidate.canonicalKey != excludedKey,
                  !answers.contains(where: { $0.canonicalKey == candidate.canonicalKey }) else { return partial }
            let p = probability(candidate, posterior: posterior, epsilon: errorFloor)
            let weight: Double = mode == .allUnknown ? 1 : Double(candidate.occurrenceCount)
            return partial + weight * min(p, 1 - p)
        }
    }

    private func updatedPosterior(for candidate: DocumentVocabularyCandidate, known: Bool) -> [Double] {
        var result = posterior
        for index in result.indices {
            let p = Self.itemProbability(theta: Self.thetaGrid[index], difficulty: candidate.difficulty, epsilon: errorFloor)
            result[index] *= known ? p : (1 - p)
        }
        Self.normalize(&result)
        return result
    }

    private func probability(_ candidate: DocumentVocabularyCandidate, posterior: [Double], epsilon: Double) -> Double {
        zip(Self.thetaGrid, posterior).reduce(0.0) { partial, pair in
            partial + pair.1 * Self.itemProbability(theta: pair.0, difficulty: candidate.difficulty, epsilon: epsilon)
        }
    }

    private func posteriorQuantile(_ quantile: Double) -> Double {
        var cumulative = 0.0
        for (theta, weight) in zip(Self.thetaGrid, posterior) {
            cumulative += weight
            if cumulative >= quantile { return theta }
        }
        return Self.thetaGrid.last ?? 6
    }

    private static func itemProbability(theta: Double, difficulty: Double, epsilon: Double) -> Double {
        epsilon + (1 - 2 * epsilon) / (1 + exp(-(theta - difficulty)))
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
