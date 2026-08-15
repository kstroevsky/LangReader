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
    let algorithmVersion: Int
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
}

private struct QualityGates: Codable {
    let eligible: Bool
    let passed: Bool
    let wellSpecifiedECE: Double
    let thetaInterval90Coverage: Double
    let coverage98HitRate: Double
}

private struct EvaluationReport: Codable {
    let schemaVersion: Int
    let configuration: Configuration
    let results: [Metrics]
    let qualityGates: QualityGates
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

    func metrics(scenario: Scenario, mode: ModeName) -> Metrics {
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
            stopReasons: stopReasons
        )
    }
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

private func candidate(index: Int, difficulty: Double, occurrenceCount: Int) -> DocumentVocabularyCandidate {
    let key = String(format: "word-%05d", index)
    return DocumentVocabularyCandidate(
        canonicalKey: key,
        displayLemma: key,
        observedForms: [VocabularyDocumentObservedForm(surface: key, occurrenceCount: occurrenceCount)],
        occurrenceCount: occurrenceCount,
        representativeRange: VocabularyDocumentSourceRange(
            unitIndex: 0,
            utf16Location: index * 8,
            utf16Length: key.utf16.count
        ),
        generalFrequencyRank: nil,
        difficulty: difficulty
    )
}

private func makeInventory(count: Int, generator: inout SeededGenerator) -> DocumentVocabularyInventory {
    var difficulties = (0..<count).map { index in
        -4 + 8 * Double(index) / Double(max(1, count - 1))
    }
    difficulties.shuffle(using: &generator)
    let candidates = difficulties.enumerated().map { index, difficulty in
        let zipf = max(1, Int((2_000 / pow(Double(index + 1), 0.82)).rounded()))
        return candidate(index: index, difficulty: difficulty, occurrenceCount: zipf)
    }
    return DocumentVocabularyInventory(languageCode: "en", candidates: candidates)
}

private func actualDifficulties(
    inventory: DocumentVocabularyInventory,
    scenario: Scenario,
    generator: inout SeededGenerator
) -> [String: Double] {
    Dictionary(uniqueKeysWithValues: inventory.candidates.map { item in
        let residual = scenario == .itemResidual ? generator.normal() * 0.8 : 0
        return (item.canonicalKey, min(max(item.difficulty + residual, -6), 6))
    })
}

private func simulateTruth(
    theta: Double,
    inventory: DocumentVocabularyInventory,
    actualDifficulties: [String: Double],
    scenario: Scenario,
    generator: inout SeededGenerator
) -> [String: Bool] {
    Dictionary(uniqueKeysWithValues: inventory.candidates.map { item in
        let difficulty = actualDifficulties[item.canonicalKey] ?? item.difficulty
        let probability = 0.05 + 0.9 * sigmoid(theta - difficulty)
        var known = generator.unit() < probability
        if scenario == .idiosyncraticKnowledge, generator.unit() < 0.12 {
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
    generator: inout SeededGenerator
) -> Metrics {
    let inventory = makeInventory(count: lemmaCount, generator: &generator)
    let actualItems = actualDifficulties(inventory: inventory, scenario: scenario, generator: &generator)
    var aggregate = Accumulator()

    for _ in 0..<readerCount {
        let theta = min(max(generator.normal() * 1.6, -5.5), 5.5)
        let truth = simulateTruth(
            theta: theta,
            inventory: inventory,
            actualDifficulties: actualItems,
            scenario: scenario,
            generator: &generator
        )
        var assessment = AdaptiveVocabularyAssessment(inventory: inventory, mode: mode.assessmentMode)
        while !assessment.isFinished, let question = assessment.nextQuestion() {
            var response = truth[question.canonicalKey] == true
            if scenario == .responseNoise, generator.unit() < 0.12 { response.toggle() }
            assessment.record(response ? .known : .unknown, for: question.canonicalKey)
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
    return aggregate.metrics(scenario: scenario, mode: mode)
}

private struct Arguments {
    var seed: UInt64 = 20_260_815
    var readers = 64
    var lemmas = 400
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
            case "--json": jsonPath = iterator.next() ?? jsonPath
            case "--markdown": markdownPath = iterator.next() ?? markdownPath
            case "--no-gate": enforceGates = false
            default:
                fputs("unknown argument: \(argument)\n", stderr)
                exit(2)
            }
        }
        guard readers > 0, lemmas >= 20 else {
            fputs("readers must be positive and lemmas must be at least 20\n", stderr)
            exit(2)
        }
    }
}

private func markdown(for report: EvaluationReport) -> String {
    var lines = [
        "# Vocabulary assessment synthetic evaluation",
        "",
        "Seed: `\(report.configuration.seed)`; readers/scenario: \(report.configuration.readersPerScenario); lemmas: \(report.configuration.lemmaCount).",
        "",
        "These are synthetic cold-start diagnostics, not evidence of calibration on real learners.",
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
                results.append(simulate(
                    scenario: scenario,
                    mode: mode,
                    readerCount: arguments.readers,
                    lemmaCount: arguments.lemmas,
                    generator: &generator
                ))
            }
        }
        let wellSpecified = results.filter { $0.scenario == Scenario.wellSpecified.rawValue }
        let wellECE = mean(wellSpecified.map(\.expectedCalibrationError))
        let intervalCoverage = mean(wellSpecified.map(\.thetaInterval90Coverage))
        let coverageHitRate = 1 - (results.first {
            $0.scenario == Scenario.wellSpecified.rawValue && $0.mode == ModeName.coverage98.rawValue
        }?.targetMissRate ?? 1)
        let eligible = arguments.readers >= 50 && arguments.lemmas >= 200
        let passed = wellECE <= 0.05
            && (0.85...0.95).contains(intervalCoverage)
            && coverageHitRate >= 0.95
        let report = EvaluationReport(
            schemaVersion: 1,
            configuration: Configuration(
                seed: arguments.seed,
                readersPerScenario: arguments.readers,
                lemmaCount: arguments.lemmas,
                algorithmVersion: VocabularyPreparationSession.currentAlgorithmVersion
            ),
            results: results,
            qualityGates: QualityGates(
                eligible: eligible,
                passed: passed,
                wellSpecifiedECE: wellECE,
                thetaInterval90Coverage: intervalCoverage,
                coverage98HitRate: coverageHitRate
            )
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
