import Foundation
import LeafReaderCore

private struct BenchmarkCase: Codable {
    let lemmaCount: Int
    let mode: String
    let warmupCount: Int
    let samplesMS: [Double]
    let p50MS: Double
    let p95MS: Double
    let maxMS: Double
    let profile: String
    let stopCheckSamplesMS: [Double]
    let stopCheckP95MS: Double
    let finalResultSamplesMS: [Double]
    let finalResultP95MS: Double
    let screeningCoverageComputationCount: Int
    let fullCoverageComputationCount: Int
    let stateUpdateSamplesMS: [Double]
    let stateUpdateP95MS: Double
    let nextQuestionSamplesMS: [Double]
    let nextQuestionP95MS: Double
    let predictiveUniqueThetaCounts: [Int]
    let predictiveUniqueThetaMedian: Double
    let predictiveUniqueThetaMaximum: Int
}

private struct AuxiliaryBenchmark: Codable {
    let name: String
    let samplesMS: [Double]
    let p50MS: Double
    let p95MS: Double
}

private struct BenchmarkReport: Codable {
    let schemaVersion: Int
    let metadata: [String: String]
    let cases: [BenchmarkCase]
    let auxiliary: [AuxiliaryBenchmark]
    let gatePassed: Bool
}

private func percentile(_ sorted: [Double], _ quantile: Double) -> Double {
    guard sorted.count > 1 else { return sorted.first ?? 0 }
    let position = quantile * Double(sorted.count - 1)
    let lower = Int(position.rounded(.down))
    let upper = Int(position.rounded(.up))
    if lower == upper { return sorted[lower] }
    return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
}

private func candidate(index: Int, count: Int) -> DocumentVocabularyCandidate {
    let key = String(format: "word-%05d", index)
    let difficulty = -4 + 8 * Double(index) / Double(max(1, count - 1))
    return DocumentVocabularyCandidate(
        canonicalKey: key,
        displayLemma: key,
        observedForms: [VocabularyDocumentObservedForm(surface: key, occurrenceCount: (index % 31) + 1)],
        occurrenceCount: (index % 31) + 1,
        representativeRange: VocabularyDocumentSourceRange(
            unitIndex: 0,
            utf16Location: index * 8,
            utf16Length: key.utf16.count
        ),
        generalFrequencyRank: nil,
        difficulty: difficulty
    )
}

private func run(
    lemmaCount: Int,
    mode: VocabularyAssessmentMode,
    modeName: String,
    readerPrior: VocabularyReaderPrior? = nil,
    profile: String = "cold",
    coverageStoppingComputation: VocabularyCoverageStoppingComputation = .fullEveryAnswer,
    reuseRepeatedPredictiveProbabilities: Bool = true,
    crossMomentQuestionScoring: Bool = true
) -> BenchmarkCase {
    let inventory = DocumentVocabularyInventory(
        languageCode: "en",
        candidates: (0..<lemmaCount).map { candidate(index: $0, count: lemmaCount) }
    )
    let warmupCount = 8
    let requestedSamples = 30
    var samples: [Double] = []
    var stopCheckSamples: [Double] = []
    var finalResultSamples: [Double] = []
    var screeningCoverageComputationCount = 0
    var fullCoverageComputationCount = 0
    var stateUpdateSamples: [Double] = []
    var nextQuestionSamples: [Double] = []
    var predictiveUniqueThetaCounts: [Int] = []
    var discarded = 0
    while samples.count < requestedSamples {
        var assessment = AdaptiveVocabularyAssessment(
            inventory: inventory,
            mode: mode,
            readerPrior: readerPrior,
            modelConfiguration: VocabularyAssessmentModelConfiguration(
                coverageStoppingComputation: coverageStoppingComputation,
                reuseRepeatedPredictiveProbabilities: reuseRepeatedPredictiveProbabilities,
                crossMomentQuestionScoring: crossMomentQuestionScoring
            )
        )
        precondition(
            assessment.usedEligibleReaderPrior == (readerPrior != nil),
            "benchmark did not execute the requested reader-prior path"
        )
        while !assessment.isFinished, let question = assessment.nextQuestion(), samples.count < requestedSamples {
            let known = question.difficulty < Double((assessment.answeredQuestionCount % 5) - 2) * 0.35
            let started = ProcessInfo.processInfo.systemUptime
            let stateUpdateStarted = ProcessInfo.processInfo.systemUptime
            assessment.record(known ? .known : .unknown, for: question.canonicalKey)
            let stateUpdateMilliseconds = (
                ProcessInfo.processInfo.systemUptime - stateUpdateStarted
            ) * 1_000
            let nextQuestionStarted = ProcessInfo.processInfo.systemUptime
            let nextQuestion = assessment.nextQuestion()
            let nextQuestionMilliseconds = (
                ProcessInfo.processInfo.systemUptime - nextQuestionStarted
            ) * 1_000
            let milliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1_000
            if nextQuestion == nil {
                stopCheckSamples.append(milliseconds)
            } else if discarded < warmupCount {
                discarded += 1
            } else {
                samples.append(milliseconds)
                stateUpdateSamples.append(stateUpdateMilliseconds)
                nextQuestionSamples.append(nextQuestionMilliseconds)
                if mode.targetCoverage != nil {
                    predictiveUniqueThetaCounts.append(
                        assessment.predictiveUniqueThetaSampleCount
                    )
                }
            }
        }
        screeningCoverageComputationCount += assessment.screeningCoverageComputationCount
        fullCoverageComputationCount += assessment.fullCoverageComputationCount
        if assessment.isFinished {
            let started = ProcessInfo.processInfo.systemUptime
            _ = assessment.result()
            finalResultSamples.append((ProcessInfo.processInfo.systemUptime - started) * 1_000)
        }
    }
    let sorted = samples.sorted()
    return BenchmarkCase(
        lemmaCount: lemmaCount,
        mode: modeName,
        warmupCount: warmupCount,
        samplesMS: samples,
        p50MS: percentile(sorted, 0.50),
        p95MS: percentile(sorted, 0.95),
        maxMS: sorted.last ?? 0,
        profile: profile,
        stopCheckSamplesMS: stopCheckSamples,
        stopCheckP95MS: percentile(stopCheckSamples.sorted(), 0.95),
        finalResultSamplesMS: finalResultSamples,
        finalResultP95MS: percentile(finalResultSamples.sorted(), 0.95),
        screeningCoverageComputationCount: screeningCoverageComputationCount,
        fullCoverageComputationCount: fullCoverageComputationCount,
        stateUpdateSamplesMS: stateUpdateSamples,
        stateUpdateP95MS: percentile(stateUpdateSamples.sorted(), 0.95),
        nextQuestionSamplesMS: nextQuestionSamples,
        nextQuestionP95MS: percentile(nextQuestionSamples.sorted(), 0.95),
        predictiveUniqueThetaCounts: predictiveUniqueThetaCounts,
        predictiveUniqueThetaMedian: percentile(
            predictiveUniqueThetaCounts.map(Double.init).sorted(),
            0.50
        ),
        predictiveUniqueThetaMaximum: predictiveUniqueThetaCounts.max() ?? 0
    )
}

private func measure(name: String, warmups: Int = 2, samples: Int = 10, body: () -> Void) -> AuxiliaryBenchmark {
    for _ in 0..<warmups { body() }
    let values = (0..<samples).map { _ -> Double in
        let started = ProcessInfo.processInfo.systemUptime
        body()
        return (ProcessInfo.processInfo.systemUptime - started) * 1_000
    }
    let sorted = values.sorted()
    return AuxiliaryBenchmark(
        name: name,
        samplesMS: values,
        p50MS: percentile(sorted, 0.50),
        p95MS: percentile(sorted, 0.95)
    )
}

private func measured(name: String, values: [Double]) -> AuxiliaryBenchmark {
    let sorted = values.sorted()
    return AuxiliaryBenchmark(
        name: name,
        samplesMS: values,
        p50MS: percentile(sorted, 0.50),
        p95MS: percentile(sorted, 0.95)
    )
}

private func coveragePhaseBenchmarks(lemmaCount: Int, samples: Int = 3) -> [AuxiliaryBenchmark] {
    let inventory = DocumentVocabularyInventory(
        languageCode: "en",
        candidates: (0..<lemmaCount).map { candidate(index: $0, count: lemmaCount) }
    )
    var stopChecks: [Double] = []
    var finalResults: [Double] = []
    let thetaGrid = (0...120).map { -6.0 + Double($0) * 0.1 }
    let storedPosterior = thetaGrid.map { exp(-pow($0 - 0.5, 2) / (2 * 0.35 * 0.35)) }
    let warmPrior = VocabularyReaderPrior(
        languageCode: "en",
        thetaPosterior: storedPosterior,
        completedSessionCount: 3,
        verifiedEvidenceCount: 80,
        lastUpdatedAt: Date(),
        algorithmVersion: VocabularyPreparationSession.currentAlgorithmVersion
    )
    for _ in 0..<samples {
        var assessment = AdaptiveVocabularyAssessment(
            inventory: inventory,
            mode: .targetCoverage(0.98),
            readerPrior: warmPrior
        )
        while !assessment.isFinished, let question = assessment.nextQuestion() {
            let started = ProcessInfo.processInfo.systemUptime
            assessment.record(.verifiedKnown, for: question.canonicalKey)
            let next = assessment.nextQuestion()
            if next == nil {
                stopChecks.append((ProcessInfo.processInfo.systemUptime - started) * 1_000)
            }
        }
        guard assessment.fullCoverageComputationCount == 1,
              stopChecks.count == finalResults.count + 1 else {
            fputs(
                "phase benchmark did not execute one staged full stop check "
                    + "(answers=\(assessment.answeredQuestionCount), "
                    + "screen=\(assessment.screeningCoverageComputationCount), "
                    + "full=\(assessment.fullCoverageComputationCount))\n",
                stderr
            )
            exit(2)
        }
        let started = ProcessInfo.processInfo.systemUptime
        _ = assessment.result()
        finalResults.append((ProcessInfo.processInfo.systemUptime - started) * 1_000)
    }
    return [
        measured(name: "coverage-stop-check-\(lemmaCount)", values: stopChecks),
        measured(name: "coverage-final-result-\(lemmaCount)", values: finalResults)
    ]
}

@main
private struct VocabularyAssessmentBenchmark {
    static func main() throws {
        let outputPath = CommandLine.arguments.dropFirst().first
            ?? "vocabulary-assessment-benchmark.json"
        let environment = ProcessInfo.processInfo.environment
        let stoppingName = environment["LEAFREADER_COVERAGE_STOPPING_COMPUTATION"]
            ?? "full-every-answer"
        guard ["full-every-answer", "staged"].contains(stoppingName) else {
            fputs("invalid LEAFREADER_COVERAGE_STOPPING_COMPUTATION\n", stderr)
            exit(2)
        }
        let stoppingComputation: VocabularyCoverageStoppingComputation = stoppingName == "staged"
            ? .staged
            : .fullEveryAnswer
        let reusePredictiveProbabilities = environment[
            "LEAFREADER_REUSE_REPEATED_PREDICTIVE_PROBABILITIES"
        ] != "0"
        let crossMomentQuestionScoring = environment[
            "LEAFREADER_CROSS_MOMENT_QUESTION_SCORING"
        ] != "0"
        let cases = [100, 1_000, 5_000, 10_000].flatMap { lemmaCount in
            [
                run(
                    lemmaCount: lemmaCount,
                    mode: .allUnknown,
                    modeName: "all-unknown",
                    coverageStoppingComputation: stoppingComputation,
                    reuseRepeatedPredictiveProbabilities: reusePredictiveProbabilities,
                    crossMomentQuestionScoring: crossMomentQuestionScoring
                ),
                run(
                    lemmaCount: lemmaCount,
                    mode: .targetCoverage(0.98),
                    modeName: "coverage-98",
                    coverageStoppingComputation: stoppingComputation,
                    reuseRepeatedPredictiveProbabilities: reusePredictiveProbabilities,
                    crossMomentQuestionScoring: crossMomentQuestionScoring
                )
            ]
        }
        let thetaGrid = (0...120).map { -6.0 + Double($0) * 0.1 }
        let storedPosterior = thetaGrid.map { exp(-pow($0 - 0.5, 2) / (2 * 0.35 * 0.35)) }
        let warmPrior = VocabularyReaderPrior(
            languageCode: "en",
            thetaPosterior: storedPosterior,
            completedSessionCount: 3,
            verifiedEvidenceCount: 80,
            lastUpdatedAt: Date(),
            algorithmVersion: VocabularyPreparationSession.currentAlgorithmVersion
        )
        let warmCase = run(
            lemmaCount: 10_000,
            mode: .targetCoverage(0.98),
            modeName: "coverage-98",
            readerPrior: warmPrior,
            profile: "warm",
            coverageStoppingComputation: stoppingComputation,
            reuseRepeatedPredictiveProbabilities: reusePredictiveProbabilities,
            crossMomentQuestionScoring: crossMomentQuestionScoring
        )
        let allCases = cases + [warmCase]
        let legacyJSON = """
        {"mode":{"allUnknown":{}},"invitationState":"started","answers":[{"canonicalKey":"word","outcome":"known","wasValidation":false}],"finalSelection":[],"algorithmVersion":2}
        """.data(using: .utf8)!
        let exportRecords = (0..<5_000).map { index in
            VocabularyResearchEvidenceRecord(
                languageCode: "en",
                lexicalItemID: VocabularyLexicalItemID(language: "en", lemma: "word-\(index)", partOfSpeech: .noun),
                documentDomain: .general,
                difficultyMean: 0,
                difficultyStandardDeviation: 0.5,
                difficultySource: .rankedFrequency,
                difficultyVersion: "benchmark",
                evidence: .verifiedKnown,
                protocolVersion: 3,
                sessionOrdinal: 1
            )
        }
        let researchExport = VocabularyResearchExport(
            participant: VocabularyResearchProfile(participantPseudonym: "benchmark"),
            records: exportRecords
        )
        var auxiliary = [
            measure(name: "session-migration") {
                _ = try? JSONDecoder().decode(VocabularyPreparationSession.self, from: legacyJSON)
            },
            measure(name: "research-export-5000") {
                _ = try? researchExport.encoded(prettyPrinted: false)
            },
            measure(name: "pos-indexing-10000-tokens", samples: 5) {
                _ = VocabularyDocumentLemmaIndex(
                    texts: [Array(repeating: "Readers develop useful vocabulary while reading books.", count: 1_667).joined(separator: " ")],
                    language: .english
                )
            }
        ]
        if stoppingComputation == .staged {
            auxiliary.append(contentsOf: coveragePhaseBenchmarks(lemmaCount: 10_000))
        }
        let largest = allCases.filter { $0.lemmaCount == 10_000 }
        let passed = largest.allSatisfy { $0.p95MS <= 150 }
        let report = BenchmarkReport(
            schemaVersion: 2,
            metadata: [
                "configuration": "release",
                "coverage_stopping_computation": stoppingName,
                "reuse_repeated_predictive_probabilities": String(reusePredictiveProbabilities),
                "cross_moment_question_scoring": String(crossMomentQuestionScoring),
                "source_revision": environment["LEAFREADER_BENCHMARK_SOURCE_REVISION"] ?? "unknown",
                "swift_version": environment["LEAFREADER_BENCHMARK_SWIFT_VERSION"] ?? "unknown",
                "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
                "processor_count": String(ProcessInfo.processInfo.processorCount)
            ],
            cases: allCases,
            auxiliary: auxiliary,
            gatePassed: passed
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(report).write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        for item in allCases {
            print(String(
                format: "%6d %@ p50=%8.3fms p95=%8.3fms max=%8.3fms",
                item.lemmaCount,
                item.mode,
                item.p50MS,
                item.p95MS,
                item.maxMS
            ))
            if item.mode == "coverage-98" {
                print(String(
                    format: "       next-card phases state-update p95=%8.3fms next-question p95=%8.3fms",
                    item.stateUpdateP95MS,
                    item.nextQuestionP95MS
                ))
                print(String(
                    format: "       predictive theta indexes median/max=%5.1f/%d of %d samples",
                    item.predictiveUniqueThetaMedian,
                    item.predictiveUniqueThetaMaximum,
                    AdaptiveVocabularyAssessment.predictiveSampleCount
                ))
            }
            if !item.stopCheckSamplesMS.isEmpty || !item.finalResultSamplesMS.isEmpty {
                print(String(
                    format: "       phases stop-check p95=%8.3fms final-result p95=%8.3fms screen/full=%d/%d",
                    item.stopCheckP95MS,
                    item.finalResultP95MS,
                    item.screeningCoverageComputationCount,
                    item.fullCoverageComputationCount
                ))
            }
        }
        for item in auxiliary {
            print(String(format: "%@ p50=%8.3fms p95=%8.3fms", item.name, item.p50MS, item.p95MS))
        }
        if !passed {
            fputs("10,000-lemma answer-to-next-card p95 exceeds 150ms\n", stderr)
            exit(1)
        }
    }
}
