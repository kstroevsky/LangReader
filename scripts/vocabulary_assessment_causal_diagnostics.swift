import Foundation
import LeafReaderCore

private enum CausalScenario: String, CaseIterable, Codable {
    case wellSpecified = "well-specified-rasch"
    case itemResidual = "item-residual"
    case responseNoise = "response-noise"
    case idiosyncraticKnowledge = "idiosyncratic-knowledge"
}

private struct CausalDiagnosticManifest: Codable {
    let schemaVersion: Int
    let dataRole: String
    let seed: UInt64
    let readers: Int
    let documents: Int
    let lemmas: Int
    let scenarios: [String]
    let fixedBudget: Int
    let targetCoverage: Double
    let b1SampleCounts: [Int]
    let b2SampleCounts: [Int]
    let replicas: Int
    let fixedControlDeckSize: Int
    let itemResidualStandardDeviation: Double
    let responseNoiseRate: Double
    let idiosyncraticFlipRate: Double
    let successDetailPolicy: String
    let b2ThetaScheme: String
    let diagnosticComparisonRule: String
    let timingRepetitions: Int
}

private struct CausalSourceProvenance: Codable {
    let revision: String
    let dirtyTree: Bool
    let dirtyStatusFingerprint: String
    let sourceContentFingerprint: String
    let swiftVersion: String
    let knowledgeModelVersion: String
    let observationModelVersion: String
    let algorithmVersion: Int
}

private struct CausalDiagnosticReport: Codable {
    let schemaVersion: Int
    let interpretation: String
    let manifest: CausalDiagnosticManifest
    let source: CausalSourceProvenance
    let runs: [CausalRunRecord]
    let replayControls: [CausalReplayControl]
    let retainedRunCounts: [String: Int]
}

private struct CausalRunRecord: Codable {
    let runID: String
    let scenario: String
    let readerID: String
    let documentID: String
    let trueTheta: Double
    let inventoryFingerprint: String
    let truthFingerprint: String
    let potentialResponseFingerprint: String
    let streamSeeds: [String: UInt64]
    let actualDifficultyVersion: String
    let natural: CausalPathRecord
    let fixedBudget: CausalPathRecord
}

private struct CausalPathRecord: Codable {
    let mode: String
    let questionCount: Int
    let stopReason: String?
    let naturalStopQuestionCount: Int?
    let naturalStopReasonBypassed: String?
    let requestedBudget: Int?
    let reachedRequestedBudget: Bool?
    let unreachableReason: String?
    let posteriorFingerprint: String
    let snapshotFingerprint: String
    let selectedKeys: [String]
    let expectedCurrentCoverage: Double
    let expectedCoverageAfterSelection: Double
    let conservativeCoverageLowerBound: Double
    let realizedProjectedCoverage: Double
    let targetShortfall: Double
    let questions: [CausalQuestionRecord]
    let forensics: CausalForensicSummary
    let items: [CausalItemRecord]
    let bankEvaluations: [CausalBankEvaluation]
}

private struct CausalQuestionRecord: Codable {
    let canonicalKey: String
    let ordinal: Int?
    let evidence: String
    let selectionType: String?
    let wasValidation: Bool
    let predictedKnown: Bool?
    let predictedKnownBeforeAnswer: Double?
}

private struct CausalBankEvaluation: Codable {
    let deckRole: String
    let replica: Int
    let result: CausalBankResultRecord
    let differenceFromProductionA: Double
    let differenceFromMatchingB1: Double?

    init(
        deckRole: String,
        replica: Int,
        result: VocabularyDiagnosticBankResult,
        differenceFromProductionA: Double = 0,
        differenceFromMatchingB1: Double? = nil
    ) {
        self.deckRole = deckRole
        self.replica = replica
        self.result = CausalBankResultRecord(result)
        self.differenceFromProductionA = differenceFromProductionA
        self.differenceFromMatchingB1 = differenceFromMatchingB1
    }

    init(
        deckRole: String,
        replica: Int,
        result: CausalBankResultRecord,
        differenceFromProductionA: Double,
        differenceFromMatchingB1: Double?
    ) {
        self.deckRole = deckRole
        self.replica = replica
        self.result = result
        self.differenceFromProductionA = differenceFromProductionA
        self.differenceFromMatchingB1 = differenceFromMatchingB1
    }
}

private struct CausalBankResultRecord: Codable {
    let kind: VocabularyDiagnosticBankKind
    let sampleCount: Int
    let coverageLowerBound: Double
    let targetMissProbability: Double
    let thetaPositionFingerprint: String
    let latentItemDrawFingerprint: String
    let uniqueThetaPositionCount: Int
    let thetaPositionHistogram: [VocabularyDiagnosticThetaPositionCount]

    init(_ result: VocabularyDiagnosticBankResult) {
        kind = result.kind
        sampleCount = result.sampleCount
        coverageLowerBound = result.coverageLowerBound
        targetMissProbability = result.targetMissProbability
        thetaPositionFingerprint = result.thetaPositionFingerprint
        latentItemDrawFingerprint = result.latentItemDrawFingerprint
        uniqueThetaPositionCount = result.uniqueThetaPositionCount
        thetaPositionHistogram = result.thetaPositionHistogram
    }
}

private struct CausalForensicSummary: Codable, Equatable {
    let claimEligible: Bool
    let assessableOccurrenceMass: Int
    let excludedOccurrenceMass: Int
    let missedMass: Int
    let answeredMissedMass: Int
    let unaskedMissedMass: Int
    let skippedMissedMassWithinUnasked: Int
    let answeredEvidenceMass: [String: Int]
    let largestMissedItemMass: Int
    let realizedProjectedCoverage: Double
    let targetShortfall: Double
}

private struct CausalItemRecord: Codable {
    let canonicalKey: String
    let displayLemma: String
    let occurrenceCount: Int
    let truthKnown: Bool
    let isSelected: Bool
    let isExcluded: Bool
    let responseState: String
    let evidence: String?
    let evidenceOrdinal: Int?
    let knownProbability: Double?
    let classification: String
    let difficultyPriorMean: Double
    let difficultyPriorStandardDeviation: Double
    let difficultySource: String
    let difficultyVersion: String
    let actualSyntheticDifficulty: Double
    let effectiveDifficultyResidualAfterClamping: Double
    let idiosyncraticFlipObserved: Bool
    let potentialResponseEvidence: String
    let potentialResponseDraw: Double
    let potentialResponseMismatchOrUncertainty: Bool
    let missedUnknownOccurrenceMass: Int
}

private struct CausalReplayControl: Codable {
    let controlID: String
    let readerID: String
    let documentID: String
    let sourcePath: String
    let destinationPrior: String
    let questionCount: Int
    let evidencePathFingerprint: String
    let sourcePosteriorFingerprint: String
    let replayPosteriorFingerprint: String
    let replaySelectedKeys: [String]
    let replayCoverageLowerBound: Double
    let interpretation: String
}

private struct CausalTimingReport: Codable {
    let schemaVersion: Int
    let semanticReportSHA256: String
    let sourceRevision: String
    let environment: [String: String]
    let workload: [String: Int]
    let repetitions: [String: [Double]]
    let repetitionCounts: [String: Int]
    let units: String
    let limitation: String
}

private struct CausalDifficultyRecord {
    let actual: Double
    let effectiveResidual: Double
}

private struct CausalTruthRecord {
    let known: Bool
    let idiosyncraticFlipObserved: Bool
}

private struct CausalPotentialResponse {
    let evidence: VocabularyKnowledgeEvidence
    let draw: Double
    let mismatchOrUncertainty: Bool
}

private struct CausalSyntheticDocument {
    let inventory: DocumentVocabularyInventory
    let difficulties: [String: CausalDifficultyRecord]
}

private struct CausalPathBuild {
    let assessment: AdaptiveVocabularyAssessment
    let record: CausalPathRecord
    let snapshotMilliseconds: Double
    let b1Milliseconds: Double
    let b2Milliseconds: Double
}

private enum CausalDiagnosticFailure: Error, CustomStringConvertible {
    case invalidManifest(String)
    case duplicateItem(String)
    case invalidWeight(String, Int)
    case missingTruth(String)
    case incompatibleSnapshot(expected: String, actual: String)
    case massConservation(String)
    case commandFailed(String)

    var description: String {
        switch self {
        case let .invalidManifest(message): "invalid causal diagnostic manifest: \(message)"
        case let .duplicateItem(key): "duplicate forensic key: \(key)"
        case let .invalidWeight(key, weight): "invalid forensic occurrence weight for \(key): \(weight)"
        case let .missingTruth(key): "missing synthetic truth for \(key)"
        case let .incompatibleSnapshot(expected, actual):
            "incompatible selection/snapshot identity: expected \(expected), got \(actual)"
        case let .massConservation(message): "forensic mass conservation failure: \(message)"
        case let .commandFailed(command): "command failed: \(command)"
        }
    }
}

private struct CausalGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func normal() -> Double {
        let first = max(unit(), 1e-12)
        return sqrt(-2 * log(first)) * cos(2 * .pi * unit())
    }
}

private struct CausalFingerprint {
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

func runVocabularyCausalDiagnosticSelfTest() throws {
    let fixture = [
        forensicFixture(key: "answered-known-error", weight: 30, truth: false, selected: false, state: "answered", evidence: .verifiedKnown),
        forensicFixture(key: "answered-unknown", weight: 10, truth: false, selected: false, state: "answered", evidence: .reportedUnknown),
        forensicFixture(key: "unasked-heavy", weight: 50, truth: false, selected: false, state: "unasked", evidence: nil),
        forensicFixture(key: "skipped", weight: 5, truth: false, selected: false, state: "skipped", evidence: nil),
        forensicFixture(key: "known", weight: 5, truth: true, selected: false, state: "unasked", evidence: nil),
        forensicFixture(key: "excluded", weight: 100, truth: false, selected: false, state: "answered", evidence: .excluded)
    ]
    let summary = try forensicSummary(
        items: fixture,
        snapshotFingerprint: "fixture",
        expectedSnapshotFingerprint: "fixture",
        targetCoverage: 0.98
    )
    precondition(summary.assessableOccurrenceMass == 100)
    precondition(summary.excludedOccurrenceMass == 100)
    precondition(summary.missedMass == 95)
    precondition(summary.answeredMissedMass == 40)
    precondition(summary.unaskedMissedMass == 55)
    precondition(summary.skippedMissedMassWithinUnasked == 5)
    precondition(summary.answeredEvidenceMass == ["reportedUnknown": 10, "verifiedKnown": 30])
    precondition(abs(summary.realizedProjectedCoverage - 0.05) < 1e-12)
    precondition(abs(summary.targetShortfall - 0.93) < 1e-12)

    let zeroMiss = try forensicSummary(
        items: [forensicFixture(key: "known", weight: 4, truth: true, selected: false, state: "unasked", evidence: nil)],
        snapshotFingerprint: "zero",
        expectedSnapshotFingerprint: "zero",
        targetCoverage: 0.98
    )
    precondition(zeroMiss.missedMass == 0 && zeroMiss.realizedProjectedCoverage == 1)

    let empty = try forensicSummary(
        items: [],
        snapshotFingerprint: "empty",
        expectedSnapshotFingerprint: "empty",
        targetCoverage: 0.98
    )
    precondition(!empty.claimEligible && empty.realizedProjectedCoverage == 1)

    do {
        _ = try forensicSummary(
            items: fixture + [fixture[0]],
            snapshotFingerprint: "fixture",
            expectedSnapshotFingerprint: "fixture",
            targetCoverage: 0.98
        )
        preconditionFailure("duplicate forensic key unexpectedly passed")
    } catch CausalDiagnosticFailure.duplicateItem {
        // Expected negative control.
    }
    do {
        _ = try forensicSummary(
            items: fixture,
            snapshotFingerprint: "one",
            expectedSnapshotFingerprint: "two",
            targetCoverage: 0.98
        )
        preconditionFailure("incompatible snapshot unexpectedly passed")
    } catch CausalDiagnosticFailure.incompatibleSnapshot {
        // Expected negative control.
    }
    print("vocabulary causal diagnostic self-test passed")
}

func runVocabularyCausalDiagnostics(
    manifestPath: String,
    jsonPath: String,
    markdownPath: String,
    timingPath: String
) throws {
    let decoder = JSONDecoder()
    let manifest = try decoder.decode(
        CausalDiagnosticManifest.self,
        from: Data(contentsOf: URL(fileURLWithPath: manifestPath))
    )
    try validate(manifest)
    let source = try sourceProvenance()
    let selectedScenarios = try manifest.scenarios.map { raw -> CausalScenario in
        guard let scenario = CausalScenario(rawValue: raw) else {
            throw CausalDiagnosticFailure.invalidManifest("unknown scenario \(raw)")
        }
        return scenario
    }

    var runs: [CausalRunRecord] = []
    var replayControls: [CausalReplayControl] = []
    var snapshotTimings: [Double] = []
    var b1Timings: [Double] = []
    var b2Timings: [Double] = []
    var replayTimings: [Double] = []

    for scenario in selectedScenarios {
        var documents: [CausalSyntheticDocument] = []
        for documentIndex in 0..<min(manifest.documents, manifest.readers) {
            let documentSeed = derivedSeed(manifest.seed, "document:\(scenario.rawValue):\(documentIndex)")
            let residualSeed = derivedSeed(manifest.seed, "item-residual:\(scenario.rawValue):\(documentIndex)")
            documents.append(makeDocument(
                lemmaCount: manifest.lemmas,
                scenario: scenario,
                itemResidualStandardDeviation: manifest.itemResidualStandardDeviation,
                documentSeed: documentSeed,
                residualSeed: residualSeed
            ))
        }

        for readerIndex in 0..<manifest.readers {
            let documentIndex = readerIndex % documents.count
            let document = documents[documentIndex]
            let thetaSeed = derivedSeed(manifest.seed, "learner-theta:\(scenario.rawValue):\(readerIndex)")
            let truthSeed = derivedSeed(
                manifest.seed,
                "learner-truth:\(scenario.rawValue):\(readerIndex):\(documentIndex)"
            )
            let responseSeed = derivedSeed(
                manifest.seed,
                "potential-response:\(scenario.rawValue):\(readerIndex):\(documentIndex):occasion-0"
            )
            var thetaGenerator = CausalGenerator(seed: thetaSeed)
            let theta = min(max(thetaGenerator.normal() * 1.6, -5.5), 5.5)
            let truths = makeTruth(
                theta: theta,
                document: document,
                scenario: scenario,
                flipRate: manifest.idiosyncraticFlipRate,
                seed: truthSeed
            )
            let responses = makePotentialResponses(
                truths: truths,
                scenario: scenario,
                responseNoiseRate: manifest.responseNoiseRate,
                inventory: document.inventory,
                seed: responseSeed
            )
            let inventoryFingerprint = fingerprint(inventory: document.inventory)
            let truthFingerprint = fingerprint(truths: truths, inventory: document.inventory)
            let responseFingerprint = fingerprint(responses: responses, inventory: document.inventory)
            let runID = "\(scenario.rawValue):reader-\(readerIndex):document-\(documentIndex)"

            let natural = try buildPath(
                pathMode: "natural",
                inventory: document.inventory,
                document: document,
                truths: truths,
                responses: responses,
                manifest: manifest,
                runID: runID,
                readerPrior: nil,
                fixedBudget: nil
            )
            let fixed = try buildPath(
                pathMode: "fixed-budget",
                inventory: document.inventory,
                document: document,
                truths: truths,
                responses: responses,
                manifest: manifest,
                runID: runID,
                readerPrior: nil,
                fixedBudget: manifest.fixedBudget
            )
            snapshotTimings.append(contentsOf: [natural.snapshotMilliseconds, fixed.snapshotMilliseconds])
            b1Timings.append(contentsOf: [natural.b1Milliseconds, fixed.b1Milliseconds])
            b2Timings.append(contentsOf: [natural.b2Milliseconds, fixed.b2Milliseconds])
            runs.append(CausalRunRecord(
                runID: runID,
                scenario: scenario.rawValue,
                readerID: "reader-\(readerIndex)",
                documentID: "\(scenario.rawValue)-document-\(documentIndex)",
                trueTheta: theta,
                inventoryFingerprint: inventoryFingerprint,
                truthFingerprint: truthFingerprint,
                potentialResponseFingerprint: responseFingerprint,
                streamSeeds: [
                    "documentConstruction": derivedSeed(manifest.seed, "document:\(scenario.rawValue):\(documentIndex)"),
                    "itemResiduals": derivedSeed(manifest.seed, "item-residual:\(scenario.rawValue):\(documentIndex)"),
                    "learnerTheta": thetaSeed,
                    "learnerTruth": truthSeed,
                    "potentialResponses": responseSeed,
                    "productionBankA": derivedSeed(manifest.seed, "record-only:core-inventory-bank-a:\(inventoryFingerprint)"),
                    "diagnosticSuccessSampling": derivedSeed(manifest.seed, "success-sampling:\(runID)")
                ],
                actualDifficultyVersion: "synthetic-prior-plus-residual-clamped-v1",
                natural: natural.record,
                fixedBudget: fixed.record
            ))

            if scenario == .wellSpecified {
                let replayStart = DispatchTime.now().uptimeNanoseconds
                replayControls.append(contentsOf: try buildReplayControls(
                    readerIndex: readerIndex,
                    documentIndex: documentIndex,
                    theta: theta,
                    document: document,
                    responses: responses,
                    naturalCold: natural.assessment,
                    targetCoverage: manifest.targetCoverage
                ))
                replayTimings.append(milliseconds(since: replayStart))
            }
        }
    }

    let report = CausalDiagnosticReport(
        schemaVersion: 1,
        interpretation: "Development-only synthetic diagnostics. Bank contrasts diagnose numerical behavior but do not prove a causal failure mechanism, calibrate real learners, or change release acceptance.",
        manifest: manifest,
        source: source,
        runs: runs,
        replayControls: replayControls,
        retainedRunCounts: [
            "allRuns": runs.count,
            "naturalFailures": runs.filter { $0.natural.targetShortfall > 0 }.count,
            "naturalSuccesses": runs.filter { $0.natural.targetShortfall == 0 }.count,
            "detailedRuns": runs.count
        ]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var serializationTimings: [Double] = []
    var reportData = Data()
    for _ in 0..<manifest.timingRepetitions {
        let start = DispatchTime.now().uptimeNanoseconds
        reportData = try encoder.encode(report)
        serializationTimings.append(milliseconds(since: start))
    }
    try reportData.write(to: URL(fileURLWithPath: jsonPath), options: .atomic)
    try causalMarkdown(report).write(
        to: URL(fileURLWithPath: markdownPath),
        atomically: true,
        encoding: .utf8
    )
    let timing = CausalTimingReport(
        schemaVersion: 1,
        semanticReportSHA256: try sha256(of: jsonPath),
        sourceRevision: source.revision,
        environment: [
            "hardware": shellOutput("uname -m"),
            "os": shellOutput("sw_vers -productVersion"),
            "swift": source.swiftVersion,
            "processCount": String(ProcessInfo.processInfo.activeProcessorCount)
        ],
        workload: [
            "readers": manifest.readers,
            "documents": min(manifest.documents, manifest.readers),
            "lemmas": manifest.lemmas,
            "runs": runs.count,
            "timingRepetitions": manifest.timingRepetitions
        ],
        repetitions: [
            "snapshotConstructionMilliseconds": snapshotTimings,
            "b1EvaluationMilliseconds": b1Timings,
            "b2EvaluationMilliseconds": b2Timings,
            "commonEvidenceReplayMilliseconds": replayTimings,
            "semanticSerializationMilliseconds": serializationTimings
        ],
        repetitionCounts: [
            "snapshotConstructionMilliseconds": snapshotTimings.count,
            "b1EvaluationMilliseconds": b1Timings.count,
            "b2EvaluationMilliseconds": b2Timings.count,
            "commonEvidenceReplayMilliseconds": replayTimings.count,
            "semanticSerializationMilliseconds": serializationTimings.count
        ],
        units: "milliseconds",
        limitation: "Wall-clock observations include host load and are intentionally excluded from the deterministic semantic report. Product 150 ms latency gates do not include this opt-in diagnostic workload."
    )
    try encoder.encode(timing).write(to: URL(fileURLWithPath: timingPath), options: .atomic)
}

private func validate(_ manifest: CausalDiagnosticManifest) throws {
    guard manifest.schemaVersion == 1 else {
        throw CausalDiagnosticFailure.invalidManifest("schemaVersion must be 1")
    }
    guard manifest.dataRole == "diagnostic-development" else {
        throw CausalDiagnosticFailure.invalidManifest("dataRole must remain diagnostic-development")
    }
    guard manifest.readers > 0, manifest.documents > 0, manifest.lemmas >= 20 else {
        throw CausalDiagnosticFailure.invalidManifest("positive readers/documents and at least 20 lemmas required")
    }
    guard (1...80).contains(manifest.fixedBudget) else {
        throw CausalDiagnosticFailure.invalidManifest("fixedBudget must be within 1...80")
    }
    guard (0...1).contains(manifest.targetCoverage), manifest.targetCoverage.isFinite else {
        throw CausalDiagnosticFailure.invalidManifest("targetCoverage must be finite within 0...1")
    }
    guard manifest.replicas > 0, manifest.timingRepetitions > 0 else {
        throw CausalDiagnosticFailure.invalidManifest("replica counts must be positive")
    }
    guard manifest.b1SampleCounts.allSatisfy({
        $0 > 0 && $0.isMultiple(of: AdaptiveVocabularyAssessment.predictiveSampleCount)
    }) else {
        throw CausalDiagnosticFailure.invalidManifest("B1 sample counts must repeat all 512 production positions")
    }
    guard manifest.b2SampleCounts.allSatisfy({ $0 > 0 && $0.isMultiple(of: 64) }) else {
        throw CausalDiagnosticFailure.invalidManifest("B2 sample counts must be positive multiples of 64")
    }
    guard manifest.successDetailPolicy == "retain-all-runs",
          manifest.b2ThetaScheme == "independent-within-stratum-jitter-v1" else {
        throw CausalDiagnosticFailure.invalidManifest("unsupported retention or B2 scheme")
    }
}

private func makeDocument(
    lemmaCount: Int,
    scenario: CausalScenario,
    itemResidualStandardDeviation: Double,
    documentSeed: UInt64,
    residualSeed: UInt64
) -> CausalSyntheticDocument {
    var documentGenerator = CausalGenerator(seed: documentSeed)
    var difficulties = (0..<lemmaCount).map { index in
        -4 + 8 * Double(index) / Double(max(1, lemmaCount - 1))
    }
    difficulties.shuffle(using: &documentGenerator)
    let candidates = difficulties.enumerated().map { index, difficulty in
        let key = String(format: "word-%05d", index)
        let count = max(1, Int((2_000 / pow(Double(index + 1), 0.82)).rounded()))
        let partOfSpeech: VocabularyPartOfSpeech = index % 10 == 0
            ? .unknown
            : (index.isMultiple(of: 2) ? .noun : .verb)
        let lexical = VocabularyLexicalItemID(language: "en", lemma: key, partOfSpeech: partOfSpeech)
        return DocumentVocabularyCandidate(
            canonicalKey: lexical.canonicalKey,
            displayLemma: key,
            lexicalItemID: lexical,
            partOfSpeech: partOfSpeech,
            observedForms: [VocabularyDocumentObservedForm(surface: key, occurrenceCount: count)],
            occurrenceCount: count,
            representativeRange: VocabularyDocumentSourceRange(
                unitIndex: 0,
                utf16Location: index * 8,
                utf16Length: key.utf16.count
            ),
            generalFrequencyRank: nil,
            difficultyPrior: VocabularyItemDifficultyPrior(
                mean: difficulty,
                standardDeviation: 0.35 + 0.4 * Double(index % 100) / 100,
                source: .rankedFrequency,
                version: "synthetic-uncertain-v3"
            )
        )
    }
    let inventory = DocumentVocabularyInventory(languageCode: "en", candidates: candidates)
    var residualGenerator = CausalGenerator(seed: residualSeed)
    let records = inventory.candidates.map { item -> (String, CausalDifficultyRecord) in
        let priorResidual = residualGenerator.normal() * item.difficultyPrior.standardDeviation
        let scenarioResidual = scenario == .itemResidual
            ? residualGenerator.normal() * itemResidualStandardDeviation
            : 0
        let actual = min(max(item.difficulty + priorResidual + scenarioResidual, -6), 6)
        return (item.canonicalKey, CausalDifficultyRecord(
            actual: actual,
            effectiveResidual: actual - item.difficulty
        ))
    }
    return CausalSyntheticDocument(inventory: inventory, difficulties: Dictionary(uniqueKeysWithValues: records))
}

private func makeTruth(
    theta: Double,
    document: CausalSyntheticDocument,
    scenario: CausalScenario,
    flipRate: Double,
    seed: UInt64
) -> [String: CausalTruthRecord] {
    var generator = CausalGenerator(seed: seed)
    return Dictionary(uniqueKeysWithValues: document.inventory.candidates.map { item in
        let actual = document.difficulties[item.canonicalKey]?.actual ?? item.difficulty
        var known = generator.unit() < 0.05 + 0.9 / (1 + exp(-(theta - actual)))
        let flipDraw = generator.unit()
        let flipped = scenario == .idiosyncraticKnowledge && flipDraw < flipRate
        if flipped { known.toggle() }
        return (item.canonicalKey, CausalTruthRecord(known: known, idiosyncraticFlipObserved: flipped))
    })
}

private func makePotentialResponses(
    truths: [String: CausalTruthRecord],
    scenario: CausalScenario,
    responseNoiseRate: Double,
    inventory: DocumentVocabularyInventory,
    seed: UInt64
) -> [String: CausalPotentialResponse] {
    var generator = CausalGenerator(seed: seed)
    return Dictionary(uniqueKeysWithValues: inventory.candidates.map { item in
        let known = truths[item.canonicalKey]?.known == true
        let draw = generator.unit()
        let evidence: VocabularyKnowledgeEvidence
        if known {
            let wrong = scenario == .responseNoise ? responseNoiseRate : 0.03
            evidence = draw < wrong ? .verifiedUnknownOrPartial : (draw < wrong + 0.03 ? .unsure : .verifiedKnown)
        } else {
            let wrong = scenario == .responseNoise ? responseNoiseRate : 0.02
            evidence = draw < wrong ? .verifiedKnown : (draw < wrong + 0.04 ? .unsure : .reportedUnknown)
        }
        return (item.canonicalKey, CausalPotentialResponse(
            evidence: evidence,
            draw: draw,
            mismatchOrUncertainty: known ? evidence != .verifiedKnown : evidence != .reportedUnknown
        ))
    })
}

private func buildPath(
    pathMode: String,
    inventory: DocumentVocabularyInventory,
    document: CausalSyntheticDocument,
    truths: [String: CausalTruthRecord],
    responses: [String: CausalPotentialResponse],
    manifest: CausalDiagnosticManifest,
    runID: String,
    readerPrior: VocabularyReaderPrior?,
    fixedBudget: Int?
) throws -> CausalPathBuild {
    var assessment = AdaptiveVocabularyAssessment(
        inventory: inventory,
        mode: .targetCoverage(manifest.targetCoverage),
        readerPrior: readerPrior,
        currentDate: Date(timeIntervalSince1970: 2_000_000_000)
    )
    var naturalStopCount: Int?
    var naturalStopReason: VocabularyAssessmentStopReason?
    var unreachableReason: String?
    while fixedBudget.map({ assessment.answeredQuestionCount < $0 }) ?? !assessment.isFinished {
        let question: DocumentVocabularyCandidate?
        if assessment.isFinished, fixedBudget != nil {
            if naturalStopCount == nil {
                naturalStopCount = assessment.answeredQuestionCount
                naturalStopReason = assessment.diagnosticNaturalStopReason
            }
            question = assessment.nextQuestionForDiagnosticContinuation()
        } else {
            question = assessment.nextQuestion()
        }
        guard let question else {
            unreachableReason = assessment.answeredQuestionCount >= 80
                ? "question-limit"
                : "candidate-exhaustion"
            break
        }
        guard let response = responses[question.canonicalKey] else {
            throw CausalDiagnosticFailure.missingTruth(question.canonicalKey)
        }
        assessment.record(response.evidence, for: question.canonicalKey)
    }
    if fixedBudget == nil {
        naturalStopCount = assessment.answeredQuestionCount
        naturalStopReason = assessment.diagnosticNaturalStopReason
    }
    let result = assessment.result()
    let snapshotStart = DispatchTime.now().uptimeNanoseconds
    let snapshot = try assessment.diagnosticSnapshot()
    let snapshotDuration = milliseconds(since: snapshotStart)
    let selected = Set(result.items.filter(\.isSelected).map(\.id))
    let controlSelection = Set(inventory.candidates.prefix(manifest.fixedControlDeckSize).map(\.canonicalKey))
    var bankEvaluations: [CausalBankEvaluation] = []
    let bankA = try snapshot.evaluate(VocabularyDiagnosticBankConfiguration(
        kind: .productionA,
        sampleCount: 512,
        thetaPositionSeed: 0,
        latentItemSeed: 0,
        targetCoverage: manifest.targetCoverage
    ))
    bankEvaluations.append(CausalBankEvaluation(deckRole: "production-selected", replica: 0, result: bankA))
    bankEvaluations.append(CausalBankEvaluation(
        deckRole: "frequency-fixed-control",
        replica: 0,
        result: try snapshot.evaluate(VocabularyDiagnosticBankConfiguration(
            kind: .productionA,
            sampleCount: 512,
            thetaPositionSeed: 0,
            latentItemSeed: 0,
            targetCoverage: manifest.targetCoverage
        ), selectedKeys: controlSelection)
    ))

    var b1Duration = 0.0
    var b2Duration = 0.0
    for sampleCount in manifest.b1SampleCounts {
        for replica in 0..<manifest.replicas {
            let latentSeed = derivedSeed(manifest.seed, "bank-b1:\(runID):\(pathMode):\(sampleCount):\(replica):latent")
            let start = DispatchTime.now().uptimeNanoseconds
            let configuration = VocabularyDiagnosticBankConfiguration(
                kind: .independentLatentB1,
                sampleCount: sampleCount,
                thetaPositionSeed: derivedSeed(manifest.seed, "bank-b1-unused-theta:\(runID):\(replica)"),
                latentItemSeed: latentSeed,
                targetCoverage: manifest.targetCoverage
            )
            bankEvaluations.append(CausalBankEvaluation(
                deckRole: "production-selected",
                replica: replica,
                result: try snapshot.evaluate(configuration)
            ))
            bankEvaluations.append(CausalBankEvaluation(
                deckRole: "frequency-fixed-control",
                replica: replica,
                result: try snapshot.evaluate(configuration, selectedKeys: controlSelection)
            ))
            b1Duration += milliseconds(since: start)
        }
    }
    for sampleCount in manifest.b2SampleCounts {
        for replica in 0..<manifest.replicas {
            let configuration = VocabularyDiagnosticBankConfiguration(
                kind: .randomizedThetaAndLatentB2,
                sampleCount: sampleCount,
                thetaPositionSeed: derivedSeed(manifest.seed, "bank-b2:\(runID):\(pathMode):\(sampleCount):\(replica):theta"),
                latentItemSeed: derivedSeed(manifest.seed, "bank-b2:\(runID):\(pathMode):\(sampleCount):\(replica):latent"),
                targetCoverage: manifest.targetCoverage
            )
            let start = DispatchTime.now().uptimeNanoseconds
            bankEvaluations.append(CausalBankEvaluation(
                deckRole: "production-selected",
                replica: replica,
                result: try snapshot.evaluate(configuration)
            ))
            bankEvaluations.append(CausalBankEvaluation(
                deckRole: "frequency-fixed-control",
                replica: replica,
                result: try snapshot.evaluate(configuration, selectedKeys: controlSelection)
            ))
            b2Duration += milliseconds(since: start)
        }
    }
    let aByRole = Dictionary(uniqueKeysWithValues: bankEvaluations.compactMap { evaluation in
        evaluation.result.kind == .productionA
            ? (evaluation.deckRole, evaluation.result.coverageLowerBound)
            : nil
    })
    bankEvaluations = bankEvaluations.map { evaluation in
        let a = aByRole[evaluation.deckRole] ?? evaluation.result.coverageLowerBound
        let matchingB1 = bankEvaluations.first {
            $0.deckRole == evaluation.deckRole
                && $0.replica == evaluation.replica
                && $0.result.sampleCount == evaluation.result.sampleCount
                && $0.result.kind == .independentLatentB1
        }
        return CausalBankEvaluation(
            deckRole: evaluation.deckRole,
            replica: evaluation.replica,
            result: evaluation.result,
            differenceFromProductionA: evaluation.result.coverageLowerBound - a,
            differenceFromMatchingB1: evaluation.result.kind == .randomizedThetaAndLatentB2
                ? matchingB1.map { evaluation.result.coverageLowerBound - $0.result.coverageLowerBound }
                : nil
        )
    }
    let itemRecords = try makeItemRecords(
        result: result,
        assessment: assessment,
        document: document,
        truths: truths,
        responses: responses
    )
    let forensics = try forensicSummary(
        items: itemRecords,
        snapshotFingerprint: snapshot.sourceFingerprint,
        expectedSnapshotFingerprint: snapshot.sourceFingerprint,
        targetCoverage: manifest.targetCoverage
    )
    let questionRecords = assessment.answers.map {
        CausalQuestionRecord(
            canonicalKey: $0.canonicalKey,
            ordinal: $0.questionOrdinal,
            evidence: $0.evidence.rawValue,
            selectionType: $0.selectionType?.rawValue,
            wasValidation: $0.wasValidation,
            predictedKnown: $0.predictedKnown,
            predictedKnownBeforeAnswer: $0.predictedKnownBeforeAnswer
        )
    }
    return CausalPathBuild(
        assessment: assessment,
        record: CausalPathRecord(
            mode: pathMode,
            questionCount: result.answeredQuestionCount,
            stopReason: result.diagnostics.stopReason?.rawValue,
            naturalStopQuestionCount: naturalStopCount,
            naturalStopReasonBypassed: fixedBudget == nil ? nil : naturalStopReason?.rawValue,
            requestedBudget: fixedBudget,
            reachedRequestedBudget: fixedBudget.map { result.answeredQuestionCount == $0 },
            unreachableReason: unreachableReason,
            posteriorFingerprint: fingerprint(posterior: assessment.thetaPosteriorSnapshot),
            snapshotFingerprint: snapshot.sourceFingerprint,
            selectedKeys: selected.sorted(),
            expectedCurrentCoverage: result.expectedCurrentCoverage,
            expectedCoverageAfterSelection: result.expectedCoverageAfterSelection,
            conservativeCoverageLowerBound: result.diagnostics.conservativeCoverageLowerBound,
            realizedProjectedCoverage: forensics.realizedProjectedCoverage,
            targetShortfall: forensics.targetShortfall,
            questions: questionRecords,
            forensics: forensics,
            items: itemRecords,
            bankEvaluations: bankEvaluations
        ),
        snapshotMilliseconds: snapshotDuration,
        b1Milliseconds: b1Duration,
        b2Milliseconds: b2Duration
    )
}

private func makeItemRecords(
    result: VocabularyAssessmentResult,
    assessment: AdaptiveVocabularyAssessment,
    document: CausalSyntheticDocument,
    truths: [String: CausalTruthRecord],
    responses: [String: CausalPotentialResponse]
) throws -> [CausalItemRecord] {
    let answerByKey = Dictionary(uniqueKeysWithValues: assessment.answers.map { ($0.canonicalKey, $0) })
    return try result.items.map { item in
        let key = item.id
        guard let truth = truths[key] else { throw CausalDiagnosticFailure.missingTruth(key) }
        guard let response = responses[key] else { throw CausalDiagnosticFailure.missingTruth(key) }
        let answer = answerByKey[key]
        let excluded = item.classification == .excluded
        let state = answer == nil ? "unasked" : "answered"
        let difficulty = document.difficulties[key] ?? CausalDifficultyRecord(
            actual: item.candidate.difficulty,
            effectiveResidual: 0
        )
        return CausalItemRecord(
            canonicalKey: key,
            displayLemma: item.candidate.displayLemma,
            occurrenceCount: item.candidate.occurrenceCount,
            truthKnown: truth.known,
            isSelected: item.isSelected,
            isExcluded: excluded,
            responseState: state,
            evidence: answer?.evidence.rawValue,
            evidenceOrdinal: answer?.questionOrdinal,
            knownProbability: excluded ? nil : item.knownProbability,
            classification: item.classification.rawValue,
            difficultyPriorMean: item.candidate.difficultyPrior.mean,
            difficultyPriorStandardDeviation: item.candidate.difficultyPrior.standardDeviation,
            difficultySource: item.candidate.difficultyPrior.source.rawValue,
            difficultyVersion: item.candidate.difficultyPrior.version,
            actualSyntheticDifficulty: difficulty.actual,
            effectiveDifficultyResidualAfterClamping: difficulty.effectiveResidual,
            idiosyncraticFlipObserved: truth.idiosyncraticFlipObserved,
            potentialResponseEvidence: response.evidence.rawValue,
            potentialResponseDraw: response.draw,
            potentialResponseMismatchOrUncertainty: response.mismatchOrUncertainty,
            missedUnknownOccurrenceMass: !excluded && !truth.known && !item.isSelected
                ? item.candidate.occurrenceCount
                : 0
        )
    }
}

private func forensicSummary(
    items: [CausalItemRecord],
    snapshotFingerprint: String,
    expectedSnapshotFingerprint: String,
    targetCoverage: Double
) throws -> CausalForensicSummary {
    guard snapshotFingerprint == expectedSnapshotFingerprint else {
        throw CausalDiagnosticFailure.incompatibleSnapshot(
            expected: expectedSnapshotFingerprint,
            actual: snapshotFingerprint
        )
    }
    var seen = Set<String>()
    var denominator = 0
    var excluded = 0
    var missed = 0
    var answered = 0
    var unasked = 0
    var skipped = 0
    var evidenceMass: [String: Int] = [:]
    var largest = 0
    for item in items {
        guard seen.insert(item.canonicalKey).inserted else {
            throw CausalDiagnosticFailure.duplicateItem(item.canonicalKey)
        }
        guard item.occurrenceCount > 0 else {
            throw CausalDiagnosticFailure.invalidWeight(item.canonicalKey, item.occurrenceCount)
        }
        if item.isExcluded {
            excluded += item.occurrenceCount
            continue
        }
        denominator += item.occurrenceCount
        guard !item.truthKnown, !item.isSelected else { continue }
        missed += item.occurrenceCount
        largest = max(largest, item.occurrenceCount)
        if item.responseState == "answered" {
            answered += item.occurrenceCount
            evidenceMass[item.evidence ?? "missing", default: 0] += item.occurrenceCount
        } else {
            unasked += item.occurrenceCount
            if item.responseState == "skipped" { skipped += item.occurrenceCount }
        }
    }
    guard answered + unasked == missed else {
        throw CausalDiagnosticFailure.massConservation("answered + unasked != missed")
    }
    guard evidenceMass.values.reduce(0, +) == answered else {
        throw CausalDiagnosticFailure.massConservation("evidence categories != answered")
    }
    let coverage = denominator == 0 ? 1 : 1 - Double(missed) / Double(denominator)
    return CausalForensicSummary(
        claimEligible: denominator > 0,
        assessableOccurrenceMass: denominator,
        excludedOccurrenceMass: excluded,
        missedMass: missed,
        answeredMissedMass: answered,
        unaskedMissedMass: unasked,
        skippedMissedMassWithinUnasked: skipped,
        answeredEvidenceMass: evidenceMass,
        largestMissedItemMass: largest,
        realizedProjectedCoverage: coverage,
        targetShortfall: max(0, targetCoverage - coverage)
    )
}

private func forensicFixture(
    key: String,
    weight: Int,
    truth: Bool,
    selected: Bool,
    state: String,
    evidence: VocabularyKnowledgeEvidence?
) -> CausalItemRecord {
    CausalItemRecord(
        canonicalKey: key,
        displayLemma: key,
        occurrenceCount: weight,
        truthKnown: truth,
        isSelected: selected,
        isExcluded: evidence == .excluded,
        responseState: state,
        evidence: evidence?.rawValue,
        evidenceOrdinal: evidence == nil ? nil : 1,
        knownProbability: evidence == .excluded ? nil : 0.5,
        classification: evidence == .excluded ? "excluded" : "uncertain",
        difficultyPriorMean: 0,
        difficultyPriorStandardDeviation: 0,
        difficultySource: "syntheticFixture",
        difficultyVersion: "fixture",
        actualSyntheticDifficulty: 0,
        effectiveDifficultyResidualAfterClamping: 0,
        idiosyncraticFlipObserved: false,
        potentialResponseEvidence: evidence?.rawValue ?? "unasked",
        potentialResponseDraw: 0.5,
        potentialResponseMismatchOrUncertainty: false,
        missedUnknownOccurrenceMass: !truth && !selected && evidence != .excluded ? weight : 0
    )
}

private func buildReplayControls(
    readerIndex: Int,
    documentIndex: Int,
    theta: Double,
    document: CausalSyntheticDocument,
    responses: [String: CausalPotentialResponse],
    naturalCold: AdaptiveVocabularyAssessment,
    targetCoverage: Double = 0.98
) throws -> [CausalReplayControl] {
    let grid = (0...120).map { -6.0 + Double($0) * 0.1 }
    let posterior = grid.map { exp(-pow($0 - theta, 2) / (2 * 0.25 * 0.25)) }
    let prior = VocabularyReaderPrior(
        languageCode: "en",
        thetaPosterior: posterior,
        completedSessionCount: 3,
        verifiedEvidenceCount: 80,
        lastUpdatedAt: Date(timeIntervalSince1970: 2_000_000_000),
        algorithmVersion: VocabularyPreparationSession.currentAlgorithmVersion
    )
    var naturalWarm = AdaptiveVocabularyAssessment(
        inventory: document.inventory,
        mode: .targetCoverage(targetCoverage),
        readerPrior: prior,
        currentDate: Date(timeIntervalSince1970: 2_000_000_001)
    )
    while !naturalWarm.isFinished, let question = naturalWarm.nextQuestion() {
        guard let response = responses[question.canonicalKey] else {
            throw CausalDiagnosticFailure.missingTruth(question.canonicalKey)
        }
        naturalWarm.record(response.evidence, for: question.canonicalKey)
    }
    let warmReplayOfCold = AdaptiveVocabularyAssessment(
        inventory: document.inventory,
        mode: .targetCoverage(targetCoverage),
        restoredAnswers: naturalCold.answers,
        readerPrior: prior,
        currentDate: Date(timeIntervalSince1970: 2_000_000_001)
    )
    let coldReplayOfWarm = AdaptiveVocabularyAssessment(
        inventory: document.inventory,
        mode: .targetCoverage(targetCoverage),
        restoredAnswers: naturalWarm.answers,
        readerPrior: nil,
        currentDate: Date(timeIntervalSince1970: 2_000_000_001)
    )
    func make(
        sourceName: String,
        destination: String,
        source: AdaptiveVocabularyAssessment,
        replay: AdaptiveVocabularyAssessment
    ) -> CausalReplayControl {
        let replayResult = replay.result()
        return CausalReplayControl(
            controlID: "reader-\(readerIndex):document-\(documentIndex):\(sourceName)-to-\(destination)",
            readerID: "reader-\(readerIndex)",
            documentID: "well-specified-rasch-document-\(documentIndex)",
            sourcePath: sourceName,
            destinationPrior: destination,
            questionCount: source.answers.count,
            evidencePathFingerprint: fingerprint(answers: source.answers),
            sourcePosteriorFingerprint: fingerprint(posterior: source.thetaPosteriorSnapshot),
            replayPosteriorFingerprint: fingerprint(posterior: replay.thetaPosteriorSnapshot),
            replaySelectedKeys: replayResult.items.filter(\.isSelected).map(\.id).sorted(),
            replayCoverageLowerBound: replayResult.diagnostics.conservativeCoverageLowerBound,
            interpretation: "Posterior comparison conditional on the fixed source question/evidence order and validation metadata; not an authentic destination-prior serving path."
        )
    }
    return [
        make(sourceName: "cold-natural", destination: "oracle-informed-warm", source: naturalCold, replay: warmReplayOfCold),
        make(sourceName: "oracle-informed-warm-natural", destination: "cold", source: naturalWarm, replay: coldReplayOfWarm)
    ]
}

private func sourceProvenance() throws -> CausalSourceProvenance {
    let revision = try checkedShellOutput("git rev-parse HEAD")
    let status = try checkedShellOutput(
        "git status --short --untracked-files=normal -- Sources Tests scripts Package.swift"
    )
    var statusFingerprint = CausalFingerprint()
    statusFingerprint.mix(status)
    return CausalSourceProvenance(
        revision: revision,
        dirtyTree: !status.isEmpty,
        dirtyStatusFingerprint: statusFingerprint.hex,
        sourceContentFingerprint: try checkedShellOutput(
            "{ git diff --binary -- Sources Tests scripts Package.swift; "
                + "git ls-files --others --exclude-standard -- Sources Tests scripts Package.swift "
                + "| LC_ALL=C sort | while IFS= read -r file; do shasum -a 256 \"$file\"; done; } "
                + "| shasum -a 256 | awk '{print $1}'"
        ),
        swiftVersion: shellOutput("swift --version").split(separator: "\n").first.map(String.init) ?? "unknown",
        knowledgeModelVersion: VocabularyKnowledgeModel.version,
        observationModelVersion: VocabularyObservationModel.version,
        algorithmVersion: VocabularyPreparationSession.currentAlgorithmVersion
    )
}

private func derivedSeed(_ base: UInt64, _ label: String) -> UInt64 {
    var fingerprint = CausalFingerprint()
    fingerprint.mix(base)
    fingerprint.mix(label)
    return UInt64(fingerprint.hex, radix: 16) ?? base
}

private func fingerprint(inventory: DocumentVocabularyInventory) -> String {
    var fingerprint = CausalFingerprint()
    fingerprint.mix(inventory.languageCode)
    for item in inventory.candidates {
        fingerprint.mix(item.canonicalKey)
        fingerprint.mix(UInt64(item.occurrenceCount))
        fingerprint.mix(item.difficultyPrior.mean.bitPattern)
        fingerprint.mix(item.difficultyPrior.standardDeviation.bitPattern)
    }
    return fingerprint.hex
}

private func fingerprint(
    truths: [String: CausalTruthRecord],
    inventory: DocumentVocabularyInventory
) -> String {
    var fingerprint = CausalFingerprint()
    for item in inventory.candidates {
        fingerprint.mix(item.canonicalKey)
        fingerprint.mix(UInt64(truths[item.canonicalKey]?.known == true ? 1 : 0))
        fingerprint.mix(UInt64(truths[item.canonicalKey]?.idiosyncraticFlipObserved == true ? 1 : 0))
    }
    return fingerprint.hex
}

private func fingerprint(
    responses: [String: CausalPotentialResponse],
    inventory: DocumentVocabularyInventory
) -> String {
    var fingerprint = CausalFingerprint()
    for item in inventory.candidates {
        fingerprint.mix(item.canonicalKey)
        fingerprint.mix(responses[item.canonicalKey]?.evidence.rawValue ?? "missing")
        fingerprint.mix(responses[item.canonicalKey]?.draw.bitPattern ?? 0)
    }
    return fingerprint.hex
}

private func fingerprint(posterior: [Double]) -> String {
    var fingerprint = CausalFingerprint()
    for value in posterior { fingerprint.mix(value.bitPattern) }
    return fingerprint.hex
}

private func fingerprint(answers: [VocabularyAssessmentAnswer]) -> String {
    var fingerprint = CausalFingerprint()
    for answer in answers {
        fingerprint.mix(answer.canonicalKey)
        fingerprint.mix(answer.evidence.rawValue)
        fingerprint.mix(UInt64(answer.questionOrdinal ?? 0))
        fingerprint.mix(answer.selectionType?.rawValue ?? "none")
        fingerprint.mix(UInt64(answer.wasValidation ? 1 : 0))
    }
    return fingerprint.hex
}

private func causalMarkdown(_ report: CausalDiagnosticReport) -> String {
    let failures = report.runs.filter { $0.natural.targetShortfall > 0 }
    let successes = report.runs.count - failures.count
    let naturalBanks = report.runs.flatMap(\.natural.bankEvaluations).filter {
        $0.deckRole == "production-selected"
    }
    let b1A = naturalBanks.filter { $0.result.kind == .independentLatentB1 }
        .map(\.differenceFromProductionA)
    let b2A = naturalBanks.filter { $0.result.kind == .randomizedThetaAndLatentB2 }
        .map(\.differenceFromProductionA)
    let b2B1 = naturalBanks.compactMap(\.differenceFromMatchingB1)
    func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
    return [
        "# Vocabulary synthetic causal diagnostics — development checkpoint",
        "",
        "Manifest schema: `\(report.manifest.schemaVersion)`; semantic schema: `\(report.schemaVersion)`; seed: `\(report.manifest.seed)`.",
        "Source: `\(report.source.revision)`; dirty tree: `\(report.source.dirtyTree)` (status fingerprint `\(report.source.dirtyStatusFingerprint)`, source-content fingerprint `\(report.source.sourceContentFingerprint)`).",
        "",
        "This is development-only synthetic evidence. It does not establish real-learner calibration, a release pass, or a unique causal explanation for a coverage miss.",
        "",
        "- Runs retained in full: \(report.runs.count) (\(failures.count) natural misses, \(successes) natural successes).",
        "- Common-question/common-evidence replay directions retained: \(report.replayControls.count).",
        String(format: "- Mean B1 − A lower-bound difference across retained natural-run replicas: %.6f.", mean(b1A)),
        String(format: "- Mean B2 − A lower-bound difference across retained natural-run replicas: %.6f.", mean(b2A)),
        String(format: "- Mean B2 − matched-B1 lower-bound difference across retained natural-run replicas: %.6f.", mean(b2B1)),
        "- B1 repeats the exact 512 production theta positions with equal mass and independent latent draws. B2 uses independent within-stratum theta jitter and independent latent draws.",
        "- The assessable denominator and missed mass use exact integers before conversion to coverage; excluded mass is reported separately.",
        "",
        "Interpretation: systematic A/B discrepancies may be consistent with finite-bank selection optimism, while agreement with isolated truth misses is not proof of model misspecification. Null and adverse runs are retained.",
        ""
    ].joined(separator: "\n")
}

private func milliseconds(since start: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}

private func shellOutput(_ command: String) -> String {
    (try? checkedShellOutput(command)) ?? "unknown"
}

private func checkedShellOutput(_ command: String) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-lc", command]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw CausalDiagnosticFailure.commandFailed(command)
    }
    return String(
        decoding: output.fileHandleForReading.readDataToEndOfFile(),
        as: UTF8.self
    ).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func sha256(of path: String) throws -> String {
    let output = try checkedShellOutput("shasum -a 256 \(shellQuoted(path))")
    return output.split(separator: " ").first.map(String.init) ?? "unknown"
}

private func shellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
