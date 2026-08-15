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
}

private struct BenchmarkReport: Codable {
    let schemaVersion: Int
    let metadata: [String: String]
    let cases: [BenchmarkCase]
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

private func run(lemmaCount: Int, mode: VocabularyAssessmentMode, modeName: String) -> BenchmarkCase {
    let inventory = DocumentVocabularyInventory(
        languageCode: "en",
        candidates: (0..<lemmaCount).map { candidate(index: $0, count: lemmaCount) }
    )
    let warmupCount = 8
    let requestedSamples = 30
    var samples: [Double] = []
    var discarded = 0
    while samples.count < requestedSamples {
        var assessment = AdaptiveVocabularyAssessment(inventory: inventory, mode: mode)
        while !assessment.isFinished, let question = assessment.nextQuestion(), samples.count < requestedSamples {
            let known = question.difficulty < Double((assessment.answeredQuestionCount % 5) - 2) * 0.35
            let started = ProcessInfo.processInfo.systemUptime
            assessment.record(known ? .known : .unknown, for: question.canonicalKey)
            _ = assessment.nextQuestion()
            let milliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1_000
            if discarded < warmupCount {
                discarded += 1
            } else {
                samples.append(milliseconds)
            }
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
        maxMS: sorted.last ?? 0
    )
}

@main
private struct VocabularyAssessmentBenchmark {
    static func main() throws {
        let outputPath = CommandLine.arguments.dropFirst().first
            ?? "vocabulary-assessment-benchmark.json"
        let cases = [100, 1_000, 5_000, 10_000].flatMap { lemmaCount in
            [
                run(lemmaCount: lemmaCount, mode: .allUnknown, modeName: "all-unknown"),
                run(lemmaCount: lemmaCount, mode: .targetCoverage(0.98), modeName: "coverage-98")
            ]
        }
        let largest = cases.filter { $0.lemmaCount == 10_000 }
        let passed = largest.allSatisfy { $0.p95MS <= 150 }
        let environment = ProcessInfo.processInfo.environment
        let report = BenchmarkReport(
            schemaVersion: 1,
            metadata: [
                "configuration": "release",
                "source_revision": environment["LEAFREADER_BENCHMARK_SOURCE_REVISION"] ?? "unknown",
                "swift_version": environment["LEAFREADER_BENCHMARK_SWIFT_VERSION"] ?? "unknown",
                "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
                "processor_count": String(ProcessInfo.processInfo.processorCount)
            ],
            cases: cases,
            gatePassed: passed
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(report).write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        for item in cases {
            print(String(
                format: "%6d %@ p50=%8.3fms p95=%8.3fms max=%8.3fms",
                item.lemmaCount,
                item.mode,
                item.p50MS,
                item.p95MS,
                item.maxMS
            ))
        }
        if !passed {
            fputs("10,000-lemma answer-to-next-card p95 exceeds 150ms\n", stderr)
            exit(1)
        }
    }
}
