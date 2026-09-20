import Foundation
import LeafReaderCore
import LeafReaderValidation

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
    var coverageStoppingComputation = "full-every-answer"
    var adaptiveLossPopulation = VocabularyAdaptiveLossPopulation.allNonExcluded
    var questionObjective = VocabularyQuestionObjective.evidenceSurrogate
    var usesPairedDiagnosticSubstreams = false
    var jsonPath = "vocabulary-assessment-quality.json"
    var markdownPath = "vocabulary-assessment-quality.md"
    var enforceGates = true
    var causalManifestPath: String?
    var causalJSONPath: String?
    var causalMarkdownPath: String?
    var causalTimingPath: String?
    var causalSelfTest = false
    var longitudinalManifestPath: String?
    var longitudinalJSONPath: String?
    var longitudinalMarkdownPath: String?
    var longitudinalTimingPath: String?
    var longitudinalSelfTest = false

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
            case "--coverage-stopping-computation":
                coverageStoppingComputation = iterator.next() ?? coverageStoppingComputation
            case "--adaptive-loss-population":
                adaptiveLossPopulation = iterator.next()
                    .flatMap(VocabularyAdaptiveLossPopulation.init(rawValue:))
                    ?? adaptiveLossPopulation
            case "--question-objective":
                questionObjective = iterator.next()
                    .flatMap(VocabularyQuestionObjective.init(rawValue:))
                    ?? questionObjective
            case "--paired-diagnostic-substreams":
                usesPairedDiagnosticSubstreams = true
            case "--json": jsonPath = iterator.next() ?? jsonPath
            case "--markdown": markdownPath = iterator.next() ?? markdownPath
            case "--no-gate": enforceGates = false
            case "--causal-manifest": causalManifestPath = iterator.next()
            case "--causal-json": causalJSONPath = iterator.next()
            case "--causal-markdown": causalMarkdownPath = iterator.next()
            case "--causal-timing": causalTimingPath = iterator.next()
            case "--causal-self-test": causalSelfTest = true
            case "--longitudinal-manifest": longitudinalManifestPath = iterator.next()
            case "--longitudinal-json": longitudinalJSONPath = iterator.next()
            case "--longitudinal-markdown": longitudinalMarkdownPath = iterator.next()
            case "--longitudinal-timing": longitudinalTimingPath = iterator.next()
            case "--longitudinal-self-test": longitudinalSelfTest = true
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
              (0...1).contains(warmPriorWeight),
              ["staged", "full-every-answer"].contains(coverageStoppingComputation) else {
            fputs("assessment model parameters are outside their supported diagnostic ranges\n", stderr)
            exit(2)
        }
    }

    var evaluationRequest: VocabularyAssessmentEvaluationRequest {
        VocabularyAssessmentEvaluationRequest(
            seed: seed,
            readers: readers,
            lemmas: lemmas,
            documents: documents,
            itemResidualStandardDeviation: itemResidualStandardDeviation,
            responseNoiseRate: responseNoiseRate,
            idiosyncraticFlipRate: idiosyncraticFlipRate,
            evidenceReliabilityScale: evidenceReliabilityScale,
            minimumEpsilonKnowledge: minimumEpsilonKnowledge,
            difficultyPriorStandardDeviationScale: difficultyPriorStandardDeviationScale,
            coverageQuantile: coverageQuantile,
            warmPriorWeight: warmPriorWeight,
            coverageStoppingComputation: coverageStoppingComputation,
            adaptiveLossPopulation: adaptiveLossPopulation,
            questionObjective: questionObjective,
            usesPairedDiagnosticSubstreams: usesPairedDiagnosticSubstreams
        )
    }
}

@main
private struct VocabularyAssessmentEvaluator {
    static func main() throws {
        let arguments = Arguments()
        if arguments.causalSelfTest {
            try runVocabularyCausalDiagnosticSelfTest()
            return
        }
        if arguments.longitudinalSelfTest {
            try runVocabularyLongitudinalSelfTest()
            return
        }
        let artifacts = try runVocabularyAssessmentEvaluation(arguments.evaluationRequest)
        try artifacts.jsonData.write(to: URL(fileURLWithPath: arguments.jsonPath), options: .atomic)
        try artifacts.markdown.write(
            to: URL(fileURLWithPath: arguments.markdownPath),
            atomically: true,
            encoding: .utf8
        )
        print(artifacts.markdown)
        if let manifestPath = arguments.causalManifestPath {
            guard let causalJSONPath = arguments.causalJSONPath,
                  let causalMarkdownPath = arguments.causalMarkdownPath,
                  let causalTimingPath = arguments.causalTimingPath else {
                fputs("causal diagnostics require --causal-json, --causal-markdown, and --causal-timing\n", stderr)
                exit(2)
            }
            let artifacts = try runVocabularyCausalDiagnostics(
                manifestData: Data(contentsOf: URL(fileURLWithPath: manifestPath))
            )
            try artifacts.jsonData.write(to: URL(fileURLWithPath: causalJSONPath), options: .atomic)
            try artifacts.markdown.write(
                to: URL(fileURLWithPath: causalMarkdownPath), atomically: true, encoding: .utf8
            )
            try artifacts.timingData.write(to: URL(fileURLWithPath: causalTimingPath), options: .atomic)
        }
        if let manifestPath = arguments.longitudinalManifestPath {
            guard let longitudinalJSONPath = arguments.longitudinalJSONPath,
                  let longitudinalMarkdownPath = arguments.longitudinalMarkdownPath,
                  let longitudinalTimingPath = arguments.longitudinalTimingPath else {
                fputs("longitudinal diagnostics require --longitudinal-json, --longitudinal-markdown, and --longitudinal-timing\n", stderr)
                exit(2)
            }
            let artifacts = try runVocabularyLongitudinalDiagnostics(
                manifestData: Data(contentsOf: URL(fileURLWithPath: manifestPath))
            )
            try artifacts.jsonData.write(to: URL(fileURLWithPath: longitudinalJSONPath), options: .atomic)
            try artifacts.markdown.write(
                to: URL(fileURLWithPath: longitudinalMarkdownPath), atomically: true, encoding: .utf8
            )
            try artifacts.timingData.write(to: URL(fileURLWithPath: longitudinalTimingPath), options: .atomic)
        }
        if arguments.enforceGates && artifacts.eligible && !artifacts.passed { exit(1) }
    }
}
