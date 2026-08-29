import Foundation
import LeafReaderCore

private enum Scenario: String, CaseIterable, Codable {
    case wellSpecified = "well-specified-rasch"
    case itemResidual = "item-residual"
    case responseNoise = "response-noise"
    case idiosyncraticKnowledge = "idiosyncratic-knowledge"
}

private enum ModeName: String, CaseIterable, Codable {
    case allUnknown = "all-unknown"
    case coverage98 = "coverage-98"

    var assessmentMode: VocabularyAssessmentMode {
        switch self {
        case .allUnknown: .allUnknown
        case .coverage98: .targetCoverage(0.98)
        }
    }
}

private struct Configuration: Codable {
    let seed: UInt64
    let readersPerScenario: Int
    let lemmaCount: Int
    let documentsPerScenario: Int
    let algorithmVersion: Int
    let populationParameters: PopulationParameters
    let assessmentModelParameters: AssessmentModelParameters
    let usesPairedDiagnosticSubstreams: Bool
}

private struct PopulationParameters: Codable {
    let itemResidualStandardDeviation: Double
    let responseNoiseRate: Double
    let idiosyncraticFlipRate: Double
}

private struct AssessmentModelParameters: Codable {
    let evidenceReliabilityScale: Double
    let minimumEpsilonKnowledge: Double
    let difficultyPriorStandardDeviationScale: Double
    let coverageQuantile: Double
    let warmPriorWeight: Double

    var coreConfiguration: VocabularyAssessmentModelConfiguration {
        VocabularyAssessmentModelConfiguration(
            evidenceReliabilityScale: evidenceReliabilityScale,
            minimumEpsilonKnowledge: minimumEpsilonKnowledge,
            coverageQuantile: coverageQuantile,
            warmPriorWeight: warmPriorWeight
        )
    }
}

private struct Metrics: Codable {
    let scenario: String
    let mode: String
    let brierScore: Double
    let logLoss: Double
    let expectedCalibrationError: Double
    let thetaRMSE: Double
    let thetaInterval90Coverage: Double
    let deckPrecision: Double
    let deckRecall: Double
    let realizedTokenCoverage: Double
    let targetMissRate: Double
    let oracleDeckRegret: Double
    let meanQuestionCount: Double
    let stopReasons: [String: Int]
    let syntheticTruthFingerprint: String?
}

private struct QualityGates: Codable {
    let eligible: Bool
    let passed: Bool
    let wellSpecifiedECE: Double
    let thetaInterval90Coverage: Double
    let coverage98HitRate: Double
    let itemResidualCoverageHitRate: Double
    let responseNoiseCoverageHitRate: Double
    let idiosyncraticCoverageHitRate: Double
    let minimumDeckPrecision: Double
    let warmStartQuestionReduction: Double
    let warmStartCoverageHitDelta: Double
}

private struct ProtocolDiagnostics: Codable {
    let responseProtocol: String
    let difficultyUncertaintyEnabled: Bool
    let partOfSpeechAmbiguityShare: Double
    let coldMeanQuestionCount: Double
    let warmMeanQuestionCount: Double
    let warmStartQuestionReduction: Double
    let coldCoverageHitRate: Double
    let warmCoverageHitRate: Double
    let syntheticTruthFingerprint: String?
}

private struct EvaluationReport: Codable {
    let schemaVersion: Int
    let configuration: Configuration
    let results: [Metrics]
    let qualityGates: QualityGates
    let protocolDiagnostics: ProtocolDiagnostics
}

private struct Accumulator {
    var probabilityTruth: [(Double, Bool)] = []
    var thetaSquaredErrors: [Double] = []
    var thetaIntervalHits: [Bool] = []
    var precision: [Double] = []
    var recall: [Double] = []
    var tokenCoverage: [Double] = []
    var targetMisses: [Bool] = []
    var oracleRegret: [Double] = []
    var questionCounts: [Double] = []
    var stopReasons: [String: Int] = [:]

    func metrics(
        scenario: Scenario,
        mode: ModeName,
        syntheticTruthFingerprint: String?
    ) -> Metrics {
        let clipped = probabilityTruth.map { (min(max($0.0, 1e-9), 1 - 1e-9), $0.1) }
        let brier = mean(clipped.map { probability, truth in
            let target = truth ? 1.0 : 0.0
            return pow(probability - target, 2)
        })
        let logLoss = mean(clipped.map { probability, truth in
            truth ? -log(probability) : -log(1 - probability)
        })
        return Metrics(
            scenario: scenario.rawValue,
            mode: mode.rawValue,
            brierScore: brier,
            logLoss: logLoss,
            expectedCalibrationError: calibrationError(clipped),
            thetaRMSE: sqrt(mean(thetaSquaredErrors)),
            thetaInterval90Coverage: mean(thetaIntervalHits.map { $0 ? 1 : 0 }),
            deckPrecision: mean(precision),
            deckRecall: mean(recall),
            realizedTokenCoverage: mean(tokenCoverage),
            targetMissRate: mean(targetMisses.map { $0 ? 1 : 0 }),
            oracleDeckRegret: mean(oracleRegret),
            meanQuestionCount: mean(questionCounts),
            stopReasons: stopReasons,
            syntheticTruthFingerprint: syntheticTruthFingerprint
        )
    }
}

private struct StableFingerprint {
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

private struct SyntheticDocument {
    let inventory: DocumentVocabularyInventory
    let actualDifficulties: [String: Double]
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func normal() -> Double {
        let first = max(unit(), 1e-12)
        let second = unit()
        return sqrt(-2 * log(first)) * cos(2 * .pi * second)
    }
}

private func diagnosticSeed(base: UInt64, label: String) -> UInt64 {
    var fingerprint = StableFingerprint()
    fingerprint.mix(base)
    fingerprint.mix(label)
    return UInt64(fingerprint.hex, radix: 16) ?? base
}

private func mean(_ values: [Double]) -> Double {
    values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
}

private func calibrationError(_ values: [(Double, Bool)]) -> Double {
    guard !values.isEmpty else { return 0 }
    var weightedError = 0.0
    for bin in 0..<10 {
        let lower = Double(bin) / 10
        let upper = Double(bin + 1) / 10
        let entries = values.filter { probability, _ in
            probability >= lower && (bin == 9 ? probability <= upper : probability < upper)
        }
        guard !entries.isEmpty else { continue }
        let confidence = mean(entries.map(\.0))
        let accuracy = mean(entries.map { $0.1 ? 1 : 0 })
        weightedError += Double(entries.count) / Double(values.count) * abs(confidence - accuracy)
    }
    return weightedError
}

private func sigmoid(_ value: Double) -> Double {
    1 / (1 + exp(-value))
}

private func candidate(
    index: Int,
    difficulty: Double,
    occurrenceCount: Int,
    difficultyPriorStandardDeviationScale: Double
) -> DocumentVocabularyCandidate {
    let key = String(format: "word-%05d", index)
    let partOfSpeech: VocabularyPartOfSpeech = index % 10 == 0 ? .unknown : (index.isMultiple(of: 2) ? .noun : .verb)
    let lexical = VocabularyLexicalItemID(language: "en", lemma: key, partOfSpeech: partOfSpeech)
    return DocumentVocabularyCandidate(
        canonicalKey: lexical.canonicalKey,
        displayLemma: key,
        lexicalItemID: lexical,
        partOfSpeech: partOfSpeech,
        observedForms: [VocabularyDocumentObservedForm(surface: key, occurrenceCount: occurrenceCount)],
        occurrenceCount: occurrenceCount,
        representativeRange: VocabularyDocumentSourceRange(
            unitIndex: 0,
            utf16Location: index * 8,
            utf16Length: key.utf16.count
        ),
        generalFrequencyRank: nil,
        difficultyPrior: VocabularyItemDifficultyPrior(
            mean: difficulty,
            standardDeviation: (
                0.35 + 0.4 * Double(index % 100) / 100
            ) * difficultyPriorStandardDeviationScale,
            source: .rankedFrequency,
            version: "synthetic-uncertain-v3"
        )
    )
}

private func makeInventory(
    count: Int,
    difficultyPriorStandardDeviationScale: Double,
    generator: inout SeededGenerator
) -> DocumentVocabularyInventory {
    var difficulties = (0..<count).map { index in
        -4 + 8 * Double(index) / Double(max(1, count - 1))
    }
    difficulties.shuffle(using: &generator)
    let candidates = difficulties.enumerated().map { index, difficulty in
        let zipf = max(1, Int((2_000 / pow(Double(index + 1), 0.82)).rounded()))
        return candidate(
            index: index,
            difficulty: difficulty,
            occurrenceCount: zipf,
            difficultyPriorStandardDeviationScale: difficultyPriorStandardDeviationScale
        )
    }
    return DocumentVocabularyInventory(languageCode: "en", candidates: candidates)
}

private func actualDifficulties(
    inventory: DocumentVocabularyInventory,
    scenario: Scenario,
    parameters: PopulationParameters,
    difficultyPriorStandardDeviationScale: Double,
    generator: inout SeededGenerator
) -> [String: Double] {
    Dictionary(uniqueKeysWithValues: inventory.candidates.map { item in
        let productionStandardDeviation = item.difficultyPrior.standardDeviation
            / difficultyPriorStandardDeviationScale
        let priorResidual = generator.normal() * productionStandardDeviation
        let residual = priorResidual + (
            scenario == .itemResidual
                ? generator.normal() * parameters.itemResidualStandardDeviation
                : 0
        )
        return (item.canonicalKey, min(max(item.difficulty + residual, -6), 6))
    })
}

private func simulatedEvidence(
    truthKnown: Bool,
    scenario: Scenario,
    parameters: PopulationParameters,
    generator: inout SeededGenerator
) -> VocabularyKnowledgeEvidence {
    let draw = generator.unit()
    if truthKnown {
        let wrong = scenario == .responseNoise ? parameters.responseNoiseRate : 0.03
        if draw < wrong { return .verifiedUnknownOrPartial }
        if draw < wrong + 0.03 { return .unsure }
        return .verifiedKnown
    }
    let wrong = scenario == .responseNoise ? parameters.responseNoiseRate : 0.02
    if draw < wrong { return .verifiedKnown }
    if draw < wrong + 0.04 { return .unsure }
    return .reportedUnknown
}

private func simulateTruth(
    theta: Double,
    inventory: DocumentVocabularyInventory,
    actualDifficulties: [String: Double],
    scenario: Scenario,
    parameters: PopulationParameters,
    generator: inout SeededGenerator
) -> [String: Bool] {
    Dictionary(uniqueKeysWithValues: inventory.candidates.map { item in
        let difficulty = actualDifficulties[item.canonicalKey] ?? item.difficulty
        let probability = 0.05 + 0.9 * sigmoid(theta - difficulty)
        var known = generator.unit() < probability
        if scenario == .idiosyncraticKnowledge,
           generator.unit() < parameters.idiosyncraticFlipRate {
            known.toggle()
        }
        return (item.canonicalKey, known)
    })
}

private func oracleDeckSize(
    inventory: DocumentVocabularyInventory,
    truth: [String: Bool],
    target: Double
) -> Int {
    let total = Double(inventory.candidates.reduce(0) { $0 + $1.occurrenceCount })
    guard total > 0 else { return 0 }
    var covered = Double(inventory.candidates.reduce(0) { partial, item in
        partial + (truth[item.canonicalKey] == true ? item.occurrenceCount : 0)
    })
    var count = 0
    for item in inventory.candidates
        .filter({ truth[$0.canonicalKey] != true })
        .sorted(by: {
            if $0.occurrenceCount != $1.occurrenceCount { return $0.occurrenceCount > $1.occurrenceCount }
            return $0.canonicalKey < $1.canonicalKey
        }) where covered / total < target {
        covered += Double(item.occurrenceCount)
        count += 1
    }
    return count
}

private func simulate(
    scenario: Scenario,
    mode: ModeName,
    readerCount: Int,
    lemmaCount: Int,
    documentCount: Int,
    parameters: PopulationParameters,
    modelParameters: AssessmentModelParameters,
    recordTruthFingerprint: Bool,
    generator: inout SeededGenerator
) -> Metrics {
    let documents = (0..<min(documentCount, readerCount)).map { _ -> SyntheticDocument in
        let inventory = makeInventory(
            count: lemmaCount,
            difficultyPriorStandardDeviationScale: modelParameters.difficultyPriorStandardDeviationScale,
            generator: &generator
        )
        return SyntheticDocument(
            inventory: inventory,
            actualDifficulties: actualDifficulties(
                inventory: inventory,
                scenario: scenario,
                parameters: parameters,
                difficultyPriorStandardDeviationScale: modelParameters.difficultyPriorStandardDeviationScale,
                generator: &generator
            )
        )
    }
    var aggregate = Accumulator()
    var truthFingerprint = StableFingerprint()
    var diagnosticTruthGenerators: [SeededGenerator] = []
    var diagnosticResponseGenerators: [SeededGenerator] = []
    if recordTruthFingerprint {
        for _ in 0..<readerCount {
            diagnosticTruthGenerators.append(SeededGenerator(seed: generator.next()))
            diagnosticResponseGenerators.append(SeededGenerator(seed: generator.next()))
        }
    }

    for readerIndex in 0..<readerCount {
        let document = documents[readerIndex % documents.count]
        let inventory = document.inventory
        let theta: Double
        let truth: [String: Bool]
        if recordTruthFingerprint {
            theta = min(max(diagnosticTruthGenerators[readerIndex].normal() * 1.6, -5.5), 5.5)
            truth = simulateTruth(
                theta: theta,
                inventory: inventory,
                actualDifficulties: document.actualDifficulties,
                scenario: scenario,
                parameters: parameters,
                generator: &diagnosticTruthGenerators[readerIndex]
            )
        } else {
            theta = min(max(generator.normal() * 1.6, -5.5), 5.5)
            truth = simulateTruth(
                theta: theta,
                inventory: inventory,
                actualDifficulties: document.actualDifficulties,
                scenario: scenario,
                parameters: parameters,
                generator: &generator
            )
        }
        if recordTruthFingerprint {
            truthFingerprint.mix(UInt64(readerIndex))
            truthFingerprint.mix(theta.bitPattern)
            for item in inventory.candidates {
                truthFingerprint.mix(item.canonicalKey)
                truthFingerprint.mix(UInt8(truth[item.canonicalKey] == true ? 1 : 0))
            }
        }
        var assessment = AdaptiveVocabularyAssessment(
            inventory: inventory,
            mode: mode.assessmentMode,
            modelConfiguration: modelParameters.coreConfiguration
        )
        while !assessment.isFinished, let question = assessment.nextQuestion() {
            let evidence: VocabularyKnowledgeEvidence
            if recordTruthFingerprint {
                evidence = simulatedEvidence(
                    truthKnown: truth[question.canonicalKey] == true,
                    scenario: scenario,
                    parameters: parameters,
                    generator: &diagnosticResponseGenerators[readerIndex]
                )
            } else {
                evidence = simulatedEvidence(
                    truthKnown: truth[question.canonicalKey] == true,
                    scenario: scenario,
                    parameters: parameters,
                    generator: &generator
                )
            }
            assessment.record(evidence, for: question.canonicalKey)
        }

        let result = assessment.result()
        let selected = Set(result.items.filter(\.isSelected).map(\.id))
        let unknown = Set(inventory.candidates.compactMap {
            truth[$0.canonicalKey] == true ? nil : $0.canonicalKey
        })
        aggregate.probabilityTruth.append(contentsOf: result.items.map {
            ($0.knownProbability, truth[$0.id] == true)
        })
        aggregate.thetaSquaredErrors.append(pow(result.diagnostics.estimatedTheta - theta, 2))
        aggregate.thetaIntervalHits.append(
            result.diagnostics.thetaLowerBound <= theta && theta <= result.diagnostics.thetaUpperBound
        )
        let selectedUnknown = selected.intersection(unknown).count
        aggregate.precision.append(selected.isEmpty ? (unknown.isEmpty ? 1 : 0) : Double(selectedUnknown) / Double(selected.count))
        aggregate.recall.append(unknown.isEmpty ? 1 : Double(selectedUnknown) / Double(unknown.count))

        let totalOccurrences = Double(inventory.candidates.reduce(0) { $0 + $1.occurrenceCount })
        let learnedOccurrences = Double(inventory.candidates.reduce(0) { partial, item in
            partial + ((truth[item.canonicalKey] == true || selected.contains(item.canonicalKey)) ? item.occurrenceCount : 0)
        })
        let coverage = totalOccurrences > 0 ? learnedOccurrences / totalOccurrences : 1
        aggregate.tokenCoverage.append(coverage)
        aggregate.targetMisses.append(mode == .coverage98 && coverage < 0.98)
        let oracle = oracleDeckSize(inventory: inventory, truth: truth, target: 0.98)
        aggregate.oracleRegret.append(Double(selected.count - oracle))
        aggregate.questionCounts.append(Double(result.answeredQuestionCount))
        let reason = result.diagnostics.stopReason?.rawValue ?? "unfinished"
        aggregate.stopReasons[reason, default: 0] += 1
    }
    return aggregate.metrics(
        scenario: scenario,
        mode: mode,
        syntheticTruthFingerprint: recordTruthFingerprint ? truthFingerprint.hex : nil
    )
}

private func warmStartDiagnostics(
    readerCount: Int,
    lemmaCount: Int,
    documentCount: Int,
    parameters: PopulationParameters,
    modelParameters: AssessmentModelParameters,
    recordTruthFingerprint: Bool,
    generator: inout SeededGenerator
) -> ProtocolDiagnostics {
    let diagnosticReaderCount = readerCount
    let documents = (0..<min(documentCount, diagnosticReaderCount)).map { _ -> SyntheticDocument in
        let inventory = makeInventory(
            count: lemmaCount,
            difficultyPriorStandardDeviationScale: modelParameters.difficultyPriorStandardDeviationScale,
            generator: &generator
        )
        return SyntheticDocument(
            inventory: inventory,
            actualDifficulties: actualDifficulties(
                inventory: inventory,
                scenario: .wellSpecified,
                parameters: parameters,
                difficultyPriorStandardDeviationScale: modelParameters.difficultyPriorStandardDeviationScale,
                generator: &generator
            )
        )
    }
    var coldCounts: [Double] = []
    var warmCounts: [Double] = []
    var coldHits: [Double] = []
    var warmHits: [Double] = []
    var truthFingerprint = StableFingerprint()
    for readerIndex in 0..<diagnosticReaderCount {
        let document = documents[readerIndex % documents.count]
        let inventory = document.inventory
        let theta = min(max(generator.normal() * 1.6, -5.5), 5.5)
        let truth = simulateTruth(
            theta: theta,
            inventory: inventory,
            actualDifficulties: document.actualDifficulties,
            scenario: .wellSpecified,
            parameters: parameters,
            generator: &generator
        )
        if recordTruthFingerprint {
            truthFingerprint.mix(UInt64(readerIndex))
            truthFingerprint.mix(theta.bitPattern)
            for item in inventory.candidates {
                truthFingerprint.mix(item.canonicalKey)
                truthFingerprint.mix(UInt8(truth[item.canonicalKey] == true ? 1 : 0))
            }
        }
        func run(prior: VocabularyReaderPrior?) -> (Int, Double) {
            var assessment = AdaptiveVocabularyAssessment(
                inventory: inventory,
                mode: .targetCoverage(0.98),
                readerPrior: prior,
                modelConfiguration: modelParameters.coreConfiguration
            )
            precondition(
                assessment.usedEligibleReaderPrior == (prior != nil),
                "warm-start diagnostic did not execute the requested prior path"
            )
            while !assessment.isFinished, let question = assessment.nextQuestion() {
                assessment.record(
                    truth[question.canonicalKey] == true ? .verifiedKnown : .reportedUnknown,
                    for: question.canonicalKey
                )
            }
            let result = assessment.result()
            if prior != nil {
                precondition(
                    assessment.answers.filter(\.wasValidation).count >= 2,
                    "warm-start diagnostic did not complete two current tail validations"
                )
            }
            let selected = Set(result.items.filter(\.isSelected).map(\.id))
            let total = Double(inventory.candidates.reduce(0) { $0 + $1.occurrenceCount })
            let covered = Double(inventory.candidates.reduce(0) { partial, item in
                partial + ((truth[item.canonicalKey] == true || selected.contains(item.canonicalKey)) ? item.occurrenceCount : 0)
            })
            return (result.answeredQuestionCount, total > 0 ? covered / total : 1)
        }
        let cold = run(prior: nil)
        let grid = (0...120).map { -6.0 + Double($0) * 0.1 }
        let posterior = grid.map { exp(-pow($0 - theta, 2) / (2 * 0.25 * 0.25)) }
        let prior = VocabularyReaderPrior(
            languageCode: "en",
            thetaPosterior: posterior,
            completedSessionCount: 3,
            verifiedEvidenceCount: 80,
            lastUpdatedAt: Date(),
            algorithmVersion: VocabularyPreparationSession.currentAlgorithmVersion
        )
        let warm = run(prior: prior)
        coldCounts.append(Double(cold.0))
        warmCounts.append(Double(warm.0))
        coldHits.append(cold.1 >= 0.98 ? 1 : 0)
        warmHits.append(warm.1 >= 0.98 ? 1 : 0)
    }
    let coldCount = mean(coldCounts)
    let warmCount = mean(warmCounts)
    let coldHit = mean(coldHits)
    let warmHit = mean(warmHits)
    return ProtocolDiagnostics(
        responseProtocol: "answer-before-reveal-verified-v3",
        difficultyUncertaintyEnabled: true,
        partOfSpeechAmbiguityShare: 0.10,
        coldMeanQuestionCount: coldCount,
        warmMeanQuestionCount: warmCount,
        warmStartQuestionReduction: coldCount > 0 ? 1 - warmCount / coldCount : 0,
        coldCoverageHitRate: coldHit,
        warmCoverageHitRate: warmHit,
        syntheticTruthFingerprint: recordTruthFingerprint ? truthFingerprint.hex : nil
    )
}

private struct Arguments {
    var seed: UInt64 = 20_260_815
    var readers = 64
    var lemmas = 400
    var documents = 8
    var itemResidualStandardDeviation = 0.8
    var responseNoiseRate = 0.12
    var idiosyncraticFlipRate = 0.12
    var evidenceReliabilityScale = 1.0
    var minimumEpsilonKnowledge = 0.05
    var difficultyPriorStandardDeviationScale = 1.0
    var coverageQuantile = 0.05
    var warmPriorWeight = 0.90
    var usesPairedDiagnosticSubstreams = false
    var jsonPath = "vocabulary-assessment-quality.json"
    var markdownPath = "vocabulary-assessment-quality.md"
    var enforceGates = true

    init() {
        var iterator = CommandLine.arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--seed": seed = iterator.next().flatMap(UInt64.init) ?? seed
            case "--readers": readers = iterator.next().flatMap(Int.init) ?? readers
            case "--lemmas": lemmas = iterator.next().flatMap(Int.init) ?? lemmas
            case "--documents": documents = iterator.next().flatMap(Int.init) ?? documents
            case "--item-residual-sd":
                itemResidualStandardDeviation = iterator.next().flatMap(Double.init) ?? itemResidualStandardDeviation
            case "--response-noise-rate":
                responseNoiseRate = iterator.next().flatMap(Double.init) ?? responseNoiseRate
            case "--idiosyncratic-flip-rate":
                idiosyncraticFlipRate = iterator.next().flatMap(Double.init) ?? idiosyncraticFlipRate
            case "--evidence-reliability-scale":
                evidenceReliabilityScale = iterator.next().flatMap(Double.init) ?? evidenceReliabilityScale
            case "--epsilon-knowledge-minimum":
                minimumEpsilonKnowledge = iterator.next().flatMap(Double.init) ?? minimumEpsilonKnowledge
            case "--difficulty-prior-sd-scale":
                difficultyPriorStandardDeviationScale = iterator.next().flatMap(Double.init)
                    ?? difficultyPriorStandardDeviationScale
            case "--coverage-quantile":
                coverageQuantile = iterator.next().flatMap(Double.init) ?? coverageQuantile
            case "--warm-prior-weight":
                warmPriorWeight = iterator.next().flatMap(Double.init) ?? warmPriorWeight
            case "--paired-diagnostic-substreams":
                usesPairedDiagnosticSubstreams = true
            case "--json": jsonPath = iterator.next() ?? jsonPath
            case "--markdown": markdownPath = iterator.next() ?? markdownPath
            case "--no-gate": enforceGates = false
            default:
                fputs("unknown argument: \(argument)\n", stderr)
                exit(2)
            }
        }
        guard readers > 0, lemmas >= 20, documents > 0 else {
            fputs("readers/documents must be positive and lemmas must be at least 20\n", stderr)
            exit(2)
        }
        guard itemResidualStandardDeviation >= 0,
              (0...0.40).contains(responseNoiseRate),
              (0...0.40).contains(idiosyncraticFlipRate) else {
            fputs("population parameters must be nonnegative and rates must be within 0...0.40\n", stderr)
            exit(2)
        }
        guard evidenceReliabilityScale >= 0,
              (0...0.25).contains(minimumEpsilonKnowledge),
              difficultyPriorStandardDeviationScale > 0,
              (0...0.5).contains(coverageQuantile),
              (0...1).contains(warmPriorWeight) else {
            fputs("assessment model parameters are outside their supported diagnostic ranges\n", stderr)
            exit(2)
        }
    }

    var populationParameters: PopulationParameters {
        PopulationParameters(
            itemResidualStandardDeviation: itemResidualStandardDeviation,
            responseNoiseRate: responseNoiseRate,
            idiosyncraticFlipRate: idiosyncraticFlipRate
        )
    }

    var assessmentModelParameters: AssessmentModelParameters {
        AssessmentModelParameters(
            evidenceReliabilityScale: evidenceReliabilityScale,
            minimumEpsilonKnowledge: minimumEpsilonKnowledge,
            difficultyPriorStandardDeviationScale: difficultyPriorStandardDeviationScale,
            coverageQuantile: coverageQuantile,
            warmPriorWeight: warmPriorWeight
        )
    }

    var effectiveDocumentCount: Int { min(documents, readers) }
}

private func markdown(for report: EvaluationReport) -> String {
    var lines = [
        "# Vocabulary assessment synthetic evaluation",
        "",
        "Seed: `\(report.configuration.seed)`; readers/scenario: \(report.configuration.readersPerScenario); documents/scenario: \(report.configuration.documentsPerScenario); lemmas/document: \(report.configuration.lemmaCount).",
        "",
        "These are synthetic cold-start diagnostics, not evidence of calibration on real learners.",
        "",
        String(
            format: "Assumed model: reliability scale %.3f; epsilon minimum %.3f; difficulty SD scale %.3f; coverage quantile %.3f; warm-prior weight %.3f.",
            report.configuration.assessmentModelParameters.evidenceReliabilityScale,
            report.configuration.assessmentModelParameters.minimumEpsilonKnowledge,
            report.configuration.assessmentModelParameters.difficultyPriorStandardDeviationScale,
            report.configuration.assessmentModelParameters.coverageQuantile,
            report.configuration.assessmentModelParameters.warmPriorWeight
        ),
        "Random stream: \(report.configuration.usesPairedDiagnosticSubstreams ? "paired diagnostic substreams" : "frozen sequential evaluator stream").",
        "",
        "| Scenario | Mode | Brier | Log loss | ECE | θ RMSE | 90% interval | Deck P/R | Token coverage | Target miss | Questions |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"
    ]
    for item in report.results {
        lines.append(String(
            format: "| %@ | %@ | %.4f | %.4f | %.4f | %.3f | %.1f%% | %.3f / %.3f | %.2f%% | %.2f%% | %.1f |",
            item.scenario,
            item.mode,
            item.brierScore,
            item.logLoss,
            item.expectedCalibrationError,
            item.thetaRMSE,
            item.thetaInterval90Coverage * 100,
            item.deckPrecision,
            item.deckRecall,
            item.realizedTokenCoverage * 100,
            item.targetMissRate * 100,
            item.meanQuestionCount
        ))
    }
    lines.append("")
    lines.append(report.qualityGates.passed ? "Quality gates: PASS." : "Quality gates: FAIL.")
    lines.append("")
    return lines.joined(separator: "\n")
}

@main
private struct VocabularyAssessmentEvaluator {
    static func main() throws {
        let arguments = Arguments()
        var generator = SeededGenerator(seed: arguments.seed)
        var results: [Metrics] = []
        for scenario in Scenario.allCases {
            for mode in ModeName.allCases {
                if arguments.usesPairedDiagnosticSubstreams {
                    var localGenerator = SeededGenerator(seed: diagnosticSeed(
                        base: arguments.seed,
                        label: "\(scenario.rawValue):\(mode.rawValue)"
                    ))
                    results.append(simulate(
                        scenario: scenario,
                        mode: mode,
                        readerCount: arguments.readers,
                        lemmaCount: arguments.lemmas,
                        documentCount: arguments.effectiveDocumentCount,
                        parameters: arguments.populationParameters,
                        modelParameters: arguments.assessmentModelParameters,
                        recordTruthFingerprint: true,
                        generator: &localGenerator
                    ))
                } else {
                    results.append(simulate(
                        scenario: scenario,
                        mode: mode,
                        readerCount: arguments.readers,
                        lemmaCount: arguments.lemmas,
                        documentCount: arguments.effectiveDocumentCount,
                        parameters: arguments.populationParameters,
                        modelParameters: arguments.assessmentModelParameters,
                        recordTruthFingerprint: false,
                        generator: &generator
                    ))
                }
            }
        }
        let protocolDiagnostics: ProtocolDiagnostics
        if arguments.usesPairedDiagnosticSubstreams {
            var warmGenerator = SeededGenerator(seed: diagnosticSeed(
                base: arguments.seed,
                label: "warm-start"
            ))
            protocolDiagnostics = warmStartDiagnostics(
                readerCount: arguments.readers,
                lemmaCount: arguments.lemmas,
                documentCount: arguments.effectiveDocumentCount,
                parameters: arguments.populationParameters,
                modelParameters: arguments.assessmentModelParameters,
                recordTruthFingerprint: true,
                generator: &warmGenerator
            )
        } else {
            protocolDiagnostics = warmStartDiagnostics(
                readerCount: arguments.readers,
                lemmaCount: arguments.lemmas,
                documentCount: arguments.effectiveDocumentCount,
                parameters: arguments.populationParameters,
                modelParameters: arguments.assessmentModelParameters,
                recordTruthFingerprint: false,
                generator: &generator
            )
        }
        let wellSpecified = results.filter { $0.scenario == Scenario.wellSpecified.rawValue }
        let wellECE = mean(wellSpecified.map(\.expectedCalibrationError))
        let intervalCoverage = mean(wellSpecified.map(\.thetaInterval90Coverage))
        let coverageHitRate = 1 - (results.first {
            $0.scenario == Scenario.wellSpecified.rawValue && $0.mode == ModeName.coverage98.rawValue
        }?.targetMissRate ?? 1)
        func coverageHit(_ scenario: Scenario) -> Double {
            1 - (results.first {
                $0.scenario == scenario.rawValue && $0.mode == ModeName.coverage98.rawValue
            }?.targetMissRate ?? 1)
        }
        let itemResidualHit = coverageHit(.itemResidual)
        let responseNoiseHit = coverageHit(.responseNoise)
        let idiosyncraticHit = coverageHit(.idiosyncraticKnowledge)
        let minimumPrecision = results.map(\.deckPrecision).min() ?? 0
        let eligible = arguments.readers >= 50
            && arguments.lemmas >= 200
            && arguments.effectiveDocumentCount >= 4
        let passed = wellECE <= 0.05
            && (0.85...0.95).contains(intervalCoverage)
            && coverageHitRate >= 0.95
            && itemResidualHit >= 0.95
            && responseNoiseHit >= 0.90
            && idiosyncraticHit >= 0.85
            && minimumPrecision >= 0.50
            && protocolDiagnostics.warmStartQuestionReduction >= 0.25
            && protocolDiagnostics.coldCoverageHitRate - protocolDiagnostics.warmCoverageHitRate <= 0.02
        let report = EvaluationReport(
            schemaVersion: 1,
            configuration: Configuration(
                seed: arguments.seed,
                readersPerScenario: arguments.readers,
                lemmaCount: arguments.lemmas,
                documentsPerScenario: arguments.effectiveDocumentCount,
                algorithmVersion: VocabularyPreparationSession.currentAlgorithmVersion,
                populationParameters: arguments.populationParameters,
                assessmentModelParameters: arguments.assessmentModelParameters,
                usesPairedDiagnosticSubstreams: arguments.usesPairedDiagnosticSubstreams
            ),
            results: results,
            qualityGates: QualityGates(
                eligible: eligible,
                passed: passed,
                wellSpecifiedECE: wellECE,
                thetaInterval90Coverage: intervalCoverage,
                coverage98HitRate: coverageHitRate
                ,itemResidualCoverageHitRate: itemResidualHit
                ,responseNoiseCoverageHitRate: responseNoiseHit
                ,idiosyncraticCoverageHitRate: idiosyncraticHit
                ,minimumDeckPrecision: minimumPrecision
                ,warmStartQuestionReduction: protocolDiagnostics.warmStartQuestionReduction
                ,warmStartCoverageHitDelta: protocolDiagnostics.warmCoverageHitRate - protocolDiagnostics.coldCoverageHitRate
            ),
            protocolDiagnostics: protocolDiagnostics
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(report)
        try data.write(to: URL(fileURLWithPath: arguments.jsonPath), options: .atomic)
        try markdown(for: report).write(
            to: URL(fileURLWithPath: arguments.markdownPath),
            atomically: true,
            encoding: .utf8
        )
        print(markdown(for: report))
        if arguments.enforceGates && eligible && !passed { exit(1) }
    }
}
