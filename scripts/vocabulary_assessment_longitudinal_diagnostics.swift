import Foundation
import LeafReaderCore

private enum LongitudinalScenario: String, CaseIterable, Codable {
    case stableOverlap = "stable-overlap"
    case noisyHistory = "noisy-history"
    case biasedSelfVerification = "biased-self-verification"
    case easyHistoryHardEvaluation = "easy-history-hard-evaluation"
    case hardHistoryEasyEvaluation = "hard-history-easy-evaluation"
    case changedDifficultyDistribution = "changed-difficulty-distribution"
    case abilityDrift = "ability-drift"
    case lowLexicalOverlap = "low-lexical-overlap"
    case insufficientHistory = "insufficient-history"
    case lowVerifiedHistory = "low-verified-history"
    case staleHistory = "stale-history"
    case futureTimestamp = "future-timestamp"
    case incompatibleVersion = "incompatible-version"
    case resetBeforeEvaluation = "reset-before-evaluation"
    case failedWriteRetry = "failed-write-retry"
    case abandonedSession = "abandoned-session"
}

private struct LongitudinalManifest: Codable {
    let schemaVersion: Int
    let dataRole: String
    let seed: UInt64
    let learnersPerScenario: Int
    let historyDocumentCount: Int
    let lemmaCount: Int
    let fixedBudget: Int
    let targetCoverage: Double
    let scenarios: [String]
    let stableOverlapShare: Double
    let lowOverlapShare: Double
    let itemResidualStandardDeviation: Double
    let learnerItemExceptionRate: Double
    let responseNoiseRate: Double
    let biasedKnownResponseRate: Double
    let abilityDrift: Double
    let difficultyShift: Double
    let b1SampleCount: Int
    let b2SampleCount: Int
    let timingRepetitions: Int
    let decisionRule: String
    let includedRunIDs: [String]?
    let traceRunIDs: [String]?
}

private struct LongitudinalSource: Codable {
    let revision: String
    let dirtyTree: Bool
    let dirtyStatusFingerprint: String
    let sourceContentFingerprint: String
    let swiftVersion: String
    let algorithmVersion: Int
}

private struct LongitudinalReport: Codable {
    let schemaVersion: Int
    let interpretation: String
    let manifest: LongitudinalManifest
    let source: LongitudinalSource
    let runs: [LongitudinalRun]
    let support: [String: Int]
}

private struct LongitudinalRun: Codable {
    let runID: String
    let scenario: String
    let learnerID: String
    let historyEvents: [LongitudinalHistoryEvent]
    let storedPrior: LongitudinalStoredPrior?
    let expectedWarmEligibility: Bool
    let coldNatural: LongitudinalPath
    let warmNatural: LongitudinalPath
    let coldFixedBudget: LongitudinalPath
    let warmFixedBudget: LongitudinalPath
    let coldPathUnderWarmPrior: LongitudinalReplay
    let warmPathUnderColdPrior: LongitudinalReplay
    let coldFixedPathUnderWarmPrior: LongitudinalReplay
    let warmFixedPathUnderColdPrior: LongitudinalReplay
    let warmCompatibility: LongitudinalWarmCompatibility
    let forensicTrace: LongitudinalForensicTrace?
    let naturalQuestionReduction: Double
    let naturalCoverageDifference: Double
    let fixedBudgetCoverageDifference: Double
    let naturalQuestionPathJaccard: Double
    let evaluationTruthFingerprint: String
    let evaluationPotentialResponseFingerprint: String
}

private struct LongitudinalHistoryEvent: Codable {
    let documentID: String
    let contributionID: String
    let disposition: String
    let completedAt: Double?
    let trueTheta: Double
    let questionCount: Int
    let usedEligiblePrior: Bool
    let requiredMinimumQuestionCount: Int
    let stopReason: String?
    let verifiedEvidenceCount: Int
    let posteriorFingerprint: String
    let initialWriteSucceeded: Bool?
    let retryWriteSucceeded: Bool?
    let duplicateWriteSucceeded: Bool?
    let storedSessionCountAfterEvent: Int
    let storedVerifiedCountAfterEvent: Int
    let storedPosteriorFingerprintAfterEvent: String?
    let storedPosteriorMatchesCompletedAssessment: Bool?
}

private struct LongitudinalStoredPrior: Codable {
    let languageCode: String
    let completedSessionCount: Int
    let verifiedEvidenceCount: Int
    let lastUpdatedAt: Double
    let algorithmVersion: Int
    let posteriorFingerprint: String
    let eligibleAtEvaluation: Bool
}

private struct LongitudinalPath: Codable {
    let priorRole: String
    let usedEligiblePrior: Bool
    let questionCount: Int
    let requiredMinimumQuestionCount: Int
    let stopReason: String?
    let naturalStopQuestionCount: Int?
    let naturalStopReasonBypassed: String?
    let requestedBudget: Int?
    let reachedRequestedBudget: Bool?
    let unreachableReason: String?
    let estimatedTheta: Double
    let thetaLowerBound: Double
    let thetaUpperBound: Double
    let brierScore: Double
    let expectedCalibrationError: Double
    let selectedCount: Int
    let selectedFingerprint: String
    let answerPathFingerprint: String
    let posteriorFingerprint: String
    let assessableOccurrenceMass: Int
    let missedOccurrenceMass: Int
    let realizedProjectedCoverage: Double
    let conservativeCoverageLowerBound: Double
    let bankA: LongitudinalBankSummary
    let bankB1: LongitudinalBankSummary
    let bankB2: LongitudinalBankSummary
    let b1MinusA: Double
    let b2MinusA: Double
    let b2MinusB1: Double
}

private struct LongitudinalBankSummary: Codable {
    let kind: VocabularyDiagnosticBankKind
    let sampleCount: Int
    let coverageLowerBound: Double
    let targetMissProbability: Double
    let thetaPositionFingerprint: String
    let latentItemDrawFingerprint: String

    init(_ result: VocabularyDiagnosticBankResult) {
        kind = result.kind
        sampleCount = result.sampleCount
        coverageLowerBound = result.coverageLowerBound
        targetMissProbability = result.targetMissProbability
        thetaPositionFingerprint = result.thetaPositionFingerprint
        latentItemDrawFingerprint = result.latentItemDrawFingerprint
    }
}

private struct LongitudinalReplay: Codable {
    let sourcePath: String
    let destinationPrior: String
    let questionCount: Int
    let answerPathFingerprint: String
    let posteriorFingerprint: String
    let estimatedTheta: Double
    let selectedCount: Int
    let selectedFingerprint: String
    let assessableOccurrenceMass: Int
    let missedOccurrenceMass: Int
    let realizedProjectedCoverage: Double
    let conservativeCoverageLowerBound: Double
    let interpretation: String
}

private struct LongitudinalWarmCompatibility: Codable {
    let applicable: Bool
    let validationQuestionOrdinals: [Int]
    let nonExcludedValidationAnswerCount: Int
    let warmEvidenceLogLikelihood: Double?
    let coldEvidenceLogLikelihood: Double?
    let evidenceLogLikelihoodRatio: Double?
    let supportsEightQuestionMinimum: Bool?
    let counterfactualMinimumApplied: Bool
    let candidatePath: LongitudinalReplay
    let candidateQuestionReduction: Double
    let candidateCoverageDifference: Double
    let interpretation: String
}

private struct LongitudinalForensicTrace: Codable {
    let paths: [LongitudinalForensicPath]
    let interpretation: String
}

private struct LongitudinalForensicPath: Codable {
    let path: String
    let questions: [LongitudinalForensicQuestion]
}

private struct LongitudinalForensicQuestion: Codable {
    let ordinal: Int
    let canonicalKey: String
    let occurrenceCount: Int
    let difficultyMean: Double
    let difficultyStandardDeviation: Double
    let truthKnown: Bool
    let learnerItemException: Bool
    let evidence: String
    let selectionType: String?
    let wasValidation: Bool
    let predictedKnownBeforeAnswer: Double?
    let finalKnownProbability: Double
    let finalClassification: String
    let selectedInFinalDeck: Bool
}

private struct LongitudinalTimingReport: Codable {
    let schemaVersion: Int
    let semanticReportSHA256: String
    let workload: [String: Int]
    let repetitions: [String: [Double]]
    let units: String
    let limitation: String
}

private struct LongitudinalDocument {
    let inventory: DocumentVocabularyInventory
    let actualDifficulty: [String: Double]
    let lexicalIndexes: [String: Int]
}

private struct LongitudinalTruth {
    let known: Bool
    let learnerItemException: Bool
}

private struct LongitudinalResponse {
    let evidence: VocabularyKnowledgeEvidence
    let draw: Double
}

private struct LongitudinalGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func normal() -> Double {
        sqrt(-2 * log(max(unit(), 1e-12))) * cos(2 * .pi * unit())
    }
}

private struct LongitudinalFingerprint {
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

private struct LongitudinalPathBuild {
    let assessment: AdaptiveVocabularyAssessment
    let path: LongitudinalPath
}

private enum LongitudinalFailure: Error, CustomStringConvertible {
    case invalidManifest(String)
    case missingValue(String)
    case invariant(String)
    case command(String)

    var description: String {
        switch self {
        case let .invalidManifest(value): "invalid longitudinal manifest: \(value)"
        case let .missingValue(value): "missing longitudinal value: \(value)"
        case let .invariant(value): "longitudinal invariant failed: \(value)"
        case let .command(value): "longitudinal command failed: \(value)"
        }
    }
}

func runVocabularyLongitudinalSelfTest() throws {
    let unavailable = VocabularyReaderPriorStore(databaseURL: nil)
    let posterior = Array(repeating: 1.0 / 121.0, count: 121)
    guard !unavailable.recordCompletedSession(
        contributionID: "unavailable",
        languageCode: "en",
        thetaPosterior: posterior,
        verifiedEvidenceCount: 40,
        completedAt: Date(timeIntervalSince1970: 100),
        algorithmVersion: VocabularyPreparationSession.currentAlgorithmVersion
    ) else {
        throw LongitudinalFailure.invariant("unavailable store accepted contribution")
    }
    let future = VocabularyReaderPrior(
        languageCode: "en",
        thetaPosterior: posterior,
        completedSessionCount: 2,
        verifiedEvidenceCount: 40,
        lastUpdatedAt: Date(timeIntervalSince1970: 101),
        algorithmVersion: VocabularyPreparationSession.currentAlgorithmVersion
    )
    guard !future.isEligible(at: Date(timeIntervalSince1970: 100)) else {
        throw LongitudinalFailure.invariant("future prior became eligible")
    }
    print("vocabulary longitudinal diagnostic self-test passed")
}

func runVocabularyLongitudinalDiagnostics(
    manifestPath: String,
    jsonPath: String,
    markdownPath: String,
    timingPath: String
) throws {
    let manifest = try JSONDecoder().decode(
        LongitudinalManifest.self,
        from: Data(contentsOf: URL(fileURLWithPath: manifestPath))
    )
    try validateLongitudinalManifest(manifest)
    let source = try longitudinalSource()
    let scenarios = try manifest.scenarios.map { raw -> LongitudinalScenario in
        guard let value = LongitudinalScenario(rawValue: raw) else {
            throw LongitudinalFailure.invalidManifest("unknown scenario \(raw)")
        }
        return value
    }
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("leafreader-longitudinal-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    var runs: [LongitudinalRun] = []
    var historyTimings: [Double] = []
    var storeTimings: [Double] = []
    var evaluationTimings: [Double] = []
    var replayTimings: [Double] = []
    let includedRunIDs = manifest.includedRunIDs.map(Set.init)
    let traceRunIDs = Set(manifest.traceRunIDs ?? [])
    for scenario in scenarios {
        for learnerIndex in 0..<manifest.learnersPerScenario {
            let runID = "\(scenario.rawValue):learner-\(learnerIndex)"
            if let includedRunIDs, !includedRunIDs.contains(runID) { continue }
            let databaseURL = root.appendingPathComponent("\(derivedLongitudinalSeed(manifest.seed, runID)).sqlite3")
            let evaluationDate = Date(timeIntervalSince1970: 2_000_000_000)
            let baseTheta = clippedNormal(seed: derivedLongitudinalSeed(manifest.seed, "theta:\(runID)"))
            let historyTheta = baseTheta
            let evaluationTheta = scenario == .abilityDrift
                ? min(5.5, max(-5.5, baseTheta + manifest.abilityDrift))
                : baseTheta
            let overlap = scenario == .lowLexicalOverlap
                ? manifest.lowOverlapShare
                : manifest.stableOverlapShare
            let plannedHistoryCount = scenario == .insufficientHistory ? 1 : manifest.historyDocumentCount
            let totalHistoryDocuments = plannedHistoryCount + (scenario == .abandonedSession ? 1 : 0)
            var historyEvents: [LongitudinalHistoryEvent] = []
            for historyIndex in 0..<totalHistoryDocuments {
                let historyStart = DispatchTime.now().uptimeNanoseconds
                let document = makeLongitudinalDocument(
                    manifest: manifest,
                    scenario: scenario,
                    phase: "history",
                    documentIndex: historyIndex,
                    overlapShare: overlap,
                    runID: runID
                )
                let truths = longitudinalTruth(
                    theta: historyTheta,
                    document: document,
                    manifest: manifest,
                    runID: runID
                )
                let responses = longitudinalResponses(
                    truths: truths,
                    document: document,
                    manifest: manifest,
                    scenario: scenario,
                    sessionID: "history-\(historyIndex)",
                    runID: runID
                )
                let isAbandoned = scenario == .abandonedSession && historyIndex == 0
                let assessment = runNaturalLongitudinalAssessment(
                    inventory: document.inventory,
                    responses: responses,
                    readerPrior: loadPrior(databaseURL, language: "en"),
                    currentDate: evaluationDate.addingTimeInterval(Double(historyIndex - totalHistoryDocuments) * 86_400),
                    target: manifest.targetCoverage,
                    maximumAnsweredQuestions: isAbandoned ? 5 : nil
                )
                historyTimings.append(longitudinalMilliseconds(since: historyStart))
                let disposition = isAbandoned
                    ? "abandoned-no-contribution"
                    : "completed"
                let completedAt = completionDate(
                    scenario: scenario,
                    evaluationDate: evaluationDate,
                    completedIndex: historyEvents.filter { $0.disposition == "completed" }.count,
                    completedCount: plannedHistoryCount
                )
                let contributionID = "\(runID):history-\(historyIndex)"
                var initial: Bool?
                var retry: Bool?
                var duplicate: Bool?
                let storeStart = DispatchTime.now().uptimeNanoseconds
                if disposition == "completed" {
                    if scenario == .failedWriteRetry, historyIndex == 0 {
                        initial = VocabularyReaderPriorStore(databaseURL: nil).recordCompletedSession(
                            contributionID: contributionID,
                            languageCode: "en",
                            thetaPosterior: assessment.thetaPosteriorSnapshot,
                            verifiedEvidenceCount: assessment.verifiedEvidenceCount,
                            completedAt: completedAt,
                            algorithmVersion: storedAlgorithmVersion(scenario)
                        )
                        retry = recordPrior(
                            databaseURL,
                            contributionID: contributionID,
                            assessment: assessment,
                            completedAt: completedAt,
                            algorithmVersion: storedAlgorithmVersion(scenario)
                        )
                    } else {
                        initial = recordPrior(
                            databaseURL,
                            contributionID: contributionID,
                            assessment: assessment,
                            completedAt: completedAt,
                            algorithmVersion: storedAlgorithmVersion(scenario)
                        )
                    }
                    duplicate = recordPrior(
                        databaseURL,
                        contributionID: contributionID,
                        assessment: assessment,
                        completedAt: completedAt,
                        algorithmVersion: storedAlgorithmVersion(scenario)
                    )
                }
                let stored = loadPrior(databaseURL, language: "en")
                storeTimings.append(longitudinalMilliseconds(since: storeStart))
                historyEvents.append(LongitudinalHistoryEvent(
                    documentID: "history-\(historyIndex)",
                    contributionID: contributionID,
                    disposition: disposition,
                    completedAt: disposition == "completed" ? completedAt.timeIntervalSince1970 : nil,
                    trueTheta: historyTheta,
                    questionCount: assessment.answeredQuestionCount,
                    usedEligiblePrior: assessment.usedEligibleReaderPrior,
                    requiredMinimumQuestionCount: assessment.requiredMinimumAnsweredQuestionCount,
                    stopReason: assessment.result().diagnostics.stopReason?.rawValue,
                    verifiedEvidenceCount: assessment.verifiedEvidenceCount,
                    posteriorFingerprint: longitudinalFingerprint(assessment.thetaPosteriorSnapshot),
                    initialWriteSucceeded: initial,
                    retryWriteSucceeded: retry,
                    duplicateWriteSucceeded: duplicate,
                    storedSessionCountAfterEvent: stored?.completedSessionCount ?? 0,
                    storedVerifiedCountAfterEvent: stored?.verifiedEvidenceCount ?? 0,
                    storedPosteriorFingerprintAfterEvent: stored.map {
                        longitudinalFingerprint($0.thetaPosterior)
                    },
                    storedPosteriorMatchesCompletedAssessment: disposition == "completed"
                        ? stored.map { approximatelyEqual($0.thetaPosterior, assessment.thetaPosteriorSnapshot) }
                        : nil
                ))
            }
            if scenario == .resetBeforeEvaluation {
                guard VocabularyReaderPriorStore(databaseURL: databaseURL).reset(languageCode: "en") else {
                    throw LongitudinalFailure.invariant("language reset failed")
                }
            }
            let prior = loadPrior(databaseURL, language: "en")
            let evaluationDocument = makeLongitudinalDocument(
                manifest: manifest,
                scenario: scenario,
                phase: "evaluation",
                documentIndex: manifest.historyDocumentCount,
                overlapShare: overlap,
                runID: runID
            )
            let evaluationTruth = longitudinalTruth(
                theta: evaluationTheta,
                document: evaluationDocument,
                manifest: manifest,
                runID: runID
            )
            let evaluationResponses = longitudinalResponses(
                truths: evaluationTruth,
                document: evaluationDocument,
                manifest: manifest,
                scenario: scenario,
                sessionID: "evaluation",
                runID: runID
            )
            let evaluationStart = DispatchTime.now().uptimeNanoseconds
            let coldNatural = try buildLongitudinalPath(
                priorRole: "cold",
                inventory: evaluationDocument.inventory,
                truths: evaluationTruth,
                responses: evaluationResponses,
                readerPrior: nil,
                currentDate: evaluationDate,
                fixedBudget: nil,
                target: manifest.targetCoverage,
                b1Samples: manifest.b1SampleCount,
                b2Samples: manifest.b2SampleCount,
                bankSeed: derivedLongitudinalSeed(manifest.seed, "banks:cold-natural:\(runID)")
            )
            let warmNatural = try buildLongitudinalPath(
                priorRole: "accumulated-warm",
                inventory: evaluationDocument.inventory,
                truths: evaluationTruth,
                responses: evaluationResponses,
                readerPrior: prior,
                currentDate: evaluationDate,
                fixedBudget: nil,
                target: manifest.targetCoverage,
                b1Samples: manifest.b1SampleCount,
                b2Samples: manifest.b2SampleCount,
                bankSeed: derivedLongitudinalSeed(manifest.seed, "banks:warm-natural:\(runID)")
            )
            let coldFixed = try buildLongitudinalPath(
                priorRole: "cold",
                inventory: evaluationDocument.inventory,
                truths: evaluationTruth,
                responses: evaluationResponses,
                readerPrior: nil,
                currentDate: evaluationDate,
                fixedBudget: manifest.fixedBudget,
                target: manifest.targetCoverage,
                b1Samples: manifest.b1SampleCount,
                b2Samples: manifest.b2SampleCount,
                bankSeed: derivedLongitudinalSeed(manifest.seed, "banks:cold-fixed:\(runID)")
            )
            let warmFixed = try buildLongitudinalPath(
                priorRole: "accumulated-warm",
                inventory: evaluationDocument.inventory,
                truths: evaluationTruth,
                responses: evaluationResponses,
                readerPrior: prior,
                currentDate: evaluationDate,
                fixedBudget: manifest.fixedBudget,
                target: manifest.targetCoverage,
                b1Samples: manifest.b1SampleCount,
                b2Samples: manifest.b2SampleCount,
                bankSeed: derivedLongitudinalSeed(manifest.seed, "banks:warm-fixed:\(runID)")
            )
            evaluationTimings.append(longitudinalMilliseconds(since: evaluationStart))
            let replayStart = DispatchTime.now().uptimeNanoseconds
            let coldUnderWarm = longitudinalReplay(
                sourcePath: "cold-natural",
                destinationPrior: "accumulated-warm",
                source: coldNatural.assessment,
                inventory: evaluationDocument.inventory,
                truths: evaluationTruth,
                readerPrior: prior,
                currentDate: evaluationDate,
                target: manifest.targetCoverage
            )
            let warmUnderCold = longitudinalReplay(
                sourcePath: "accumulated-warm-natural",
                destinationPrior: "cold",
                source: warmNatural.assessment,
                inventory: evaluationDocument.inventory,
                truths: evaluationTruth,
                readerPrior: nil,
                currentDate: evaluationDate,
                target: manifest.targetCoverage
            )
            let coldFixedUnderWarm = longitudinalReplay(
                sourcePath: "cold-fixed-budget",
                destinationPrior: "accumulated-warm",
                source: coldFixed.assessment,
                inventory: evaluationDocument.inventory,
                truths: evaluationTruth,
                readerPrior: prior,
                currentDate: evaluationDate,
                target: manifest.targetCoverage
            )
            let warmFixedUnderCold = longitudinalReplay(
                sourcePath: "accumulated-warm-fixed-budget",
                destinationPrior: "cold",
                source: warmFixed.assessment,
                inventory: evaluationDocument.inventory,
                truths: evaluationTruth,
                readerPrior: nil,
                currentDate: evaluationDate,
                target: manifest.targetCoverage
            )
            let compatibility = longitudinalWarmCompatibility(
                coldNatural: coldNatural,
                warmNatural: warmNatural,
                warmFixed: warmFixed,
                inventory: evaluationDocument.inventory,
                truths: evaluationTruth,
                readerPrior: prior,
                currentDate: evaluationDate,
                target: manifest.targetCoverage
            )
            replayTimings.append(longitudinalMilliseconds(since: replayStart))
            let stored = prior.map { value in
                LongitudinalStoredPrior(
                    languageCode: value.languageCode,
                    completedSessionCount: value.completedSessionCount,
                    verifiedEvidenceCount: value.verifiedEvidenceCount,
                    lastUpdatedAt: value.lastUpdatedAt.timeIntervalSince1970,
                    algorithmVersion: value.algorithmVersion,
                    posteriorFingerprint: longitudinalFingerprint(value.thetaPosterior),
                    eligibleAtEvaluation: value.isEligible(at: evaluationDate)
                )
            }
            let coldKeys = Set(coldNatural.assessment.answers.map(\.canonicalKey))
            let warmKeys = Set(warmNatural.assessment.answers.map(\.canonicalKey))
            let union = coldKeys.union(warmKeys)
            let forensicTrace: LongitudinalForensicTrace?
            if traceRunIDs.contains(runID) {
                forensicTrace = try longitudinalForensicTrace(
                    paths: [
                        ("coldNatural", coldNatural.assessment),
                        ("warmNatural", warmNatural.assessment),
                        ("coldFixedBudget", coldFixed.assessment),
                        ("warmFixedBudget", warmFixed.assessment)
                    ],
                    inventory: evaluationDocument.inventory,
                    truths: evaluationTruth
                )
            } else {
                forensicTrace = nil
            }
            runs.append(LongitudinalRun(
                runID: runID,
                scenario: scenario.rawValue,
                learnerID: "learner-\(learnerIndex)",
                historyEvents: historyEvents,
                storedPrior: stored,
                expectedWarmEligibility: prior.map {
                    $0.algorithmVersion == VocabularyPreparationSession.currentAlgorithmVersion
                        && $0.languageCode == "en"
                        && $0.isEligible(at: evaluationDate)
                } ?? false,
                coldNatural: coldNatural.path,
                warmNatural: warmNatural.path,
                coldFixedBudget: coldFixed.path,
                warmFixedBudget: warmFixed.path,
                coldPathUnderWarmPrior: coldUnderWarm,
                warmPathUnderColdPrior: warmUnderCold,
                coldFixedPathUnderWarmPrior: coldFixedUnderWarm,
                warmFixedPathUnderColdPrior: warmFixedUnderCold,
                warmCompatibility: compatibility,
                forensicTrace: forensicTrace,
                naturalQuestionReduction: coldNatural.path.questionCount > 0
                    ? 1 - Double(warmNatural.path.questionCount) / Double(coldNatural.path.questionCount)
                    : 0,
                naturalCoverageDifference: warmNatural.path.realizedProjectedCoverage
                    - coldNatural.path.realizedProjectedCoverage,
                fixedBudgetCoverageDifference: warmFixed.path.realizedProjectedCoverage
                    - coldFixed.path.realizedProjectedCoverage,
                naturalQuestionPathJaccard: union.isEmpty
                    ? 1
                    : Double(coldKeys.intersection(warmKeys).count) / Double(union.count),
                evaluationTruthFingerprint: longitudinalTruthFingerprint(
                    evaluationTruth,
                    inventory: evaluationDocument.inventory
                ),
                evaluationPotentialResponseFingerprint: longitudinalResponseFingerprint(
                    evaluationResponses,
                    inventory: evaluationDocument.inventory
                )
            ))
        }
    }
    let report = LongitudinalReport(
        schemaVersion: traceRunIDs.isEmpty ? 3 : 4,
        interpretation: "Development-only synthetic longitudinal evidence using the production SQLite prior store and completion contract. Oracle-informed warm diagnostics remain separate; this report is not real-learner calibration or release acceptance.",
        manifest: manifest,
        source: source,
        runs: runs,
        support: [
            "runs": runs.count,
            "eligibleWarmRuns": runs.filter(\.expectedWarmEligibility).count,
            "ineligibleWarmRuns": runs.filter { !$0.expectedWarmEligibility }.count,
            "naturalWarmPriorUsed": runs.filter(\.warmNatural.usedEligiblePrior).count
        ]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var data = Data()
    var serializationTimings: [Double] = []
    for _ in 0..<manifest.timingRepetitions {
        let start = DispatchTime.now().uptimeNanoseconds
        data = try encoder.encode(report)
        serializationTimings.append(longitudinalMilliseconds(since: start))
    }
    try data.write(to: URL(fileURLWithPath: jsonPath), options: .atomic)
    try longitudinalMarkdown(report).write(
        to: URL(fileURLWithPath: markdownPath),
        atomically: true,
        encoding: .utf8
    )
    let timing = LongitudinalTimingReport(
        schemaVersion: 1,
        semanticReportSHA256: try longitudinalSHA256(jsonPath),
        workload: [
            "runs": runs.count,
            "historyEvents": runs.flatMap(\.historyEvents).count,
            "lemmaCount": manifest.lemmaCount,
            "timingRepetitions": manifest.timingRepetitions
        ],
        repetitions: [
            "historyAssessmentMilliseconds": historyTimings,
            "storeRoundTripMilliseconds": storeTimings,
            "fourEvaluationPathsMilliseconds": evaluationTimings,
            "fourReplayPathsMilliseconds": replayTimings,
            "semanticSerializationMilliseconds": serializationTimings
        ],
        units: "milliseconds",
        limitation: "Wall-clock observations include host load and are separate from product latency gates. Temporary database creation and cleanup are outside the per-round-trip spans."
    )
    try encoder.encode(timing).write(to: URL(fileURLWithPath: timingPath), options: .atomic)
}

private func validateLongitudinalManifest(_ manifest: LongitudinalManifest) throws {
    guard manifest.schemaVersion == 1, manifest.dataRole == "diagnostic-development" else {
        throw LongitudinalFailure.invalidManifest("schema/data role")
    }
    guard manifest.learnersPerScenario > 0,
          manifest.historyDocumentCount >= 2,
          manifest.lemmaCount >= 20,
          (1...80).contains(manifest.fixedBudget),
          (0...1).contains(manifest.targetCoverage),
          manifest.b1SampleCount.isMultiple(of: 512),
          manifest.b2SampleCount.isMultiple(of: 64),
          manifest.timingRepetitions > 0 else {
        throw LongitudinalFailure.invalidManifest("counts or probabilities")
    }
    let scenarios = Set(manifest.scenarios)
    func validateRunID(_ runID: String) -> Bool {
        let parts = runID.components(separatedBy: ":learner-")
        guard parts.count == 2,
              scenarios.contains(parts[0]),
              let learner = Int(parts[1]),
              (0..<manifest.learnersPerScenario).contains(learner) else {
            return false
        }
        return true
    }
    if let included = manifest.includedRunIDs {
        guard !included.isEmpty,
              Set(included).count == included.count,
              included.allSatisfy(validateRunID) else {
            throw LongitudinalFailure.invalidManifest("included run IDs")
        }
    }
    if let traced = manifest.traceRunIDs {
        let allowed = Set(manifest.includedRunIDs ?? traced)
        guard Set(traced).count == traced.count,
              traced.allSatisfy(validateRunID),
              Set(traced).isSubset(of: allowed) else {
            throw LongitudinalFailure.invalidManifest("trace run IDs")
        }
    }
}

private func makeLongitudinalDocument(
    manifest: LongitudinalManifest,
    scenario: LongitudinalScenario,
    phase: String,
    documentIndex: Int,
    overlapShare: Double,
    runID: String
) -> LongitudinalDocument {
    let sharedCount = min(manifest.lemmaCount, max(0, Int(Double(manifest.lemmaCount) * overlapShare)))
    let uniqueCount = manifest.lemmaCount - sharedCount
    let uniqueStart = sharedCount + documentIndex * uniqueCount
    let indexes = Array(0..<sharedCount) + Array(uniqueStart..<(uniqueStart + uniqueCount))
    let maximumIndex = max(1, sharedCount + (manifest.historyDocumentCount + 2) * max(1, uniqueCount))
    let candidates = indexes.enumerated().map { localIndex, lexicalIndex in
        let lemma = String(format: "long-word-%05d", lexicalIndex)
        let partOfSpeech: VocabularyPartOfSpeech = lexicalIndex.isMultiple(of: 2) ? .noun : .verb
        let lexicalID = VocabularyLexicalItemID(language: "en", lemma: lemma, partOfSpeech: partOfSpeech)
        let mean = -4 + 8 * Double(lexicalIndex % maximumIndex) / Double(maximumIndex)
        let count = max(1, Int((1_000 / pow(Double(localIndex + 1), 0.78)).rounded()))
        return DocumentVocabularyCandidate(
            canonicalKey: lexicalID.canonicalKey,
            displayLemma: lemma,
            lexicalItemID: lexicalID,
            partOfSpeech: partOfSpeech,
            observedForms: [VocabularyDocumentObservedForm(surface: lemma, occurrenceCount: count)],
            occurrenceCount: count,
            representativeRange: VocabularyDocumentSourceRange(
                unitIndex: documentIndex,
                utf16Location: localIndex * 12,
                utf16Length: lemma.utf16.count
            ),
            generalFrequencyRank: nil,
            difficultyPrior: VocabularyItemDifficultyPrior(
                mean: mean,
                standardDeviation: 0.35 + 0.4 * Double(lexicalIndex % 100) / 100,
                source: .rankedFrequency,
                version: "longitudinal-synthetic-v1"
            )
        )
    }
    let inventory = DocumentVocabularyInventory(languageCode: "en", candidates: candidates)
    var actual: [String: Double] = [:]
    var lexicalIndexes: [String: Int] = [:]
    for (lexicalIndex, candidate) in zip(indexes, candidates) {
        var generator = LongitudinalGenerator(
            seed: derivedLongitudinalSeed(manifest.seed, "item-effect:\(runID):\(lexicalIndex)")
        )
        let itemResidual = generator.normal() * manifest.itemResidualStandardDeviation
        let phaseShift: Double
        switch (scenario, phase) {
        case (.easyHistoryHardEvaluation, "history"): phaseShift = -manifest.difficultyShift
        case (.easyHistoryHardEvaluation, _): phaseShift = manifest.difficultyShift
        case (.hardHistoryEasyEvaluation, "history"): phaseShift = manifest.difficultyShift
        case (.hardHistoryEasyEvaluation, _): phaseShift = -manifest.difficultyShift
        case (.changedDifficultyDistribution, "evaluation"): phaseShift = manifest.difficultyShift
        default: phaseShift = 0
        }
        actual[candidate.canonicalKey] = min(6, max(-6, candidate.difficulty + itemResidual + phaseShift))
        lexicalIndexes[candidate.canonicalKey] = lexicalIndex
    }
    return LongitudinalDocument(inventory: inventory, actualDifficulty: actual, lexicalIndexes: lexicalIndexes)
}

private func longitudinalTruth(
    theta: Double,
    document: LongitudinalDocument,
    manifest: LongitudinalManifest,
    runID: String
) -> [String: LongitudinalTruth] {
    Dictionary(uniqueKeysWithValues: document.inventory.candidates.map { candidate in
        let lexicalIndex = document.lexicalIndexes[candidate.canonicalKey] ?? 0
        var generator = LongitudinalGenerator(
            seed: derivedLongitudinalSeed(manifest.seed, "truth:\(runID):\(lexicalIndex)")
        )
        let difficulty = document.actualDifficulty[candidate.canonicalKey] ?? candidate.difficulty
        var known = generator.unit() < 0.05 + 0.9 / (1 + exp(-(theta - difficulty)))
        let exception = generator.unit() < manifest.learnerItemExceptionRate
        if exception { known.toggle() }
        return (candidate.canonicalKey, LongitudinalTruth(known: known, learnerItemException: exception))
    })
}

private func longitudinalResponses(
    truths: [String: LongitudinalTruth],
    document: LongitudinalDocument,
    manifest: LongitudinalManifest,
    scenario: LongitudinalScenario,
    sessionID: String,
    runID: String
) -> [String: LongitudinalResponse] {
    Dictionary(uniqueKeysWithValues: document.inventory.candidates.map { candidate in
        var generator = LongitudinalGenerator(
            seed: derivedLongitudinalSeed(
                manifest.seed,
                "response:\(runID):\(sessionID):\(candidate.canonicalKey):occasion-0"
            )
        )
        let draw = generator.unit()
        let known = truths[candidate.canonicalKey]?.known == true
        let evidence: VocabularyKnowledgeEvidence
        if scenario == .lowVerifiedHistory, sessionID.hasPrefix("history") {
            evidence = known ? .legacyKnown : .legacyUnknown
        } else if scenario == .biasedSelfVerification, !known, draw < manifest.biasedKnownResponseRate {
            evidence = .verifiedKnown
        } else if known {
            let noise = scenario == .noisyHistory && sessionID.hasPrefix("history")
                ? manifest.responseNoiseRate
                : 0.03
            evidence = draw < noise ? .verifiedUnknownOrPartial : (draw < noise + 0.03 ? .unsure : .verifiedKnown)
        } else {
            let noise = scenario == .noisyHistory && sessionID.hasPrefix("history")
                ? manifest.responseNoiseRate
                : 0.02
            evidence = draw < noise ? .verifiedKnown : (draw < noise + 0.04 ? .unsure : .reportedUnknown)
        }
        return (candidate.canonicalKey, LongitudinalResponse(evidence: evidence, draw: draw))
    })
}

private func runNaturalLongitudinalAssessment(
    inventory: DocumentVocabularyInventory,
    responses: [String: LongitudinalResponse],
    readerPrior: VocabularyReaderPrior?,
    currentDate: Date,
    target: Double,
    maximumAnsweredQuestions: Int? = nil
) -> AdaptiveVocabularyAssessment {
    var assessment = AdaptiveVocabularyAssessment(
        inventory: inventory,
        mode: .targetCoverage(target),
        readerPrior: readerPrior,
        currentDate: currentDate
    )
    while !assessment.isFinished,
          maximumAnsweredQuestions.map({ assessment.answeredQuestionCount < $0 }) ?? true,
          let question = assessment.nextQuestion() {
        assessment.record(responses[question.canonicalKey]?.evidence ?? .unsure, for: question.canonicalKey)
    }
    return assessment
}

private func buildLongitudinalPath(
    priorRole: String,
    inventory: DocumentVocabularyInventory,
    truths: [String: LongitudinalTruth],
    responses: [String: LongitudinalResponse],
    readerPrior: VocabularyReaderPrior?,
    currentDate: Date,
    fixedBudget: Int?,
    target: Double,
    b1Samples: Int,
    b2Samples: Int,
    bankSeed: UInt64
) throws -> LongitudinalPathBuild {
    var assessment = AdaptiveVocabularyAssessment(
        inventory: inventory,
        mode: .targetCoverage(target),
        readerPrior: readerPrior,
        currentDate: currentDate
    )
    var naturalStopCount: Int?
    var naturalStopReason: VocabularyAssessmentStopReason?
    var unreachable: String?
    while fixedBudget.map({ assessment.answeredQuestionCount < $0 }) ?? !assessment.isFinished {
        let question: DocumentVocabularyCandidate?
        if fixedBudget != nil, assessment.isFinished {
            if naturalStopCount == nil {
                naturalStopCount = assessment.answeredQuestionCount
                naturalStopReason = assessment.diagnosticNaturalStopReason
            }
            question = assessment.nextQuestionForDiagnosticContinuation()
        } else {
            question = assessment.nextQuestion()
        }
        guard let question else {
            unreachable = assessment.answeredQuestionCount >= 80 ? "question-limit" : "candidate-exhaustion"
            break
        }
        guard let response = responses[question.canonicalKey] else {
            throw LongitudinalFailure.missingValue("response \(question.canonicalKey)")
        }
        assessment.record(response.evidence, for: question.canonicalKey)
    }
    if fixedBudget == nil {
        naturalStopCount = assessment.answeredQuestionCount
        naturalStopReason = assessment.diagnosticNaturalStopReason
    }
    let result = assessment.result()
    let snapshot = try assessment.diagnosticSnapshot()
    let bankA = try snapshot.evaluate(VocabularyDiagnosticBankConfiguration(
        kind: .productionA,
        sampleCount: 512,
        thetaPositionSeed: 0,
        latentItemSeed: 0,
        targetCoverage: target
    ))
    let bankB1 = try snapshot.evaluate(VocabularyDiagnosticBankConfiguration(
        kind: .independentLatentB1,
        sampleCount: b1Samples,
        thetaPositionSeed: derivedLongitudinalSeed(bankSeed, "b1-unused-theta"),
        latentItemSeed: derivedLongitudinalSeed(bankSeed, "b1-latent"),
        targetCoverage: target
    ))
    let bankB2 = try snapshot.evaluate(VocabularyDiagnosticBankConfiguration(
        kind: .randomizedThetaAndLatentB2,
        sampleCount: b2Samples,
        thetaPositionSeed: derivedLongitudinalSeed(bankSeed, "b2-theta"),
        latentItemSeed: derivedLongitudinalSeed(bankSeed, "b2-latent"),
        targetCoverage: target
    ))
    let selected = Set(result.items.filter(\.isSelected).map(\.id))
    let included = result.items.filter { $0.classification != .excluded }
    let denominator = included.reduce(0) { $0 + $1.candidate.occurrenceCount }
    let missed = included.reduce(0) { partial, item in
        partial + (truths[item.id]?.known == false && !selected.contains(item.id)
            ? item.candidate.occurrenceCount
            : 0)
    }
    let probabilityTruth = included.map { ($0.knownProbability, truths[$0.id]?.known == true) }
    let coverage = denominator == 0 ? 1 : 1 - Double(missed) / Double(denominator)
    return LongitudinalPathBuild(
        assessment: assessment,
        path: LongitudinalPath(
            priorRole: priorRole,
            usedEligiblePrior: assessment.usedEligibleReaderPrior,
            questionCount: assessment.answeredQuestionCount,
            requiredMinimumQuestionCount: assessment.requiredMinimumAnsweredQuestionCount,
            stopReason: result.diagnostics.stopReason?.rawValue,
            naturalStopQuestionCount: naturalStopCount,
            naturalStopReasonBypassed: fixedBudget == nil ? nil : naturalStopReason?.rawValue,
            requestedBudget: fixedBudget,
            reachedRequestedBudget: fixedBudget.map { assessment.answeredQuestionCount == $0 },
            unreachableReason: unreachable,
            estimatedTheta: result.diagnostics.estimatedTheta,
            thetaLowerBound: result.diagnostics.thetaLowerBound,
            thetaUpperBound: result.diagnostics.thetaUpperBound,
            brierScore: longitudinalMean(probabilityTruth.map {
                let target = $0.1 ? 1.0 : 0.0
                return pow($0.0 - target, 2)
            }),
            expectedCalibrationError: longitudinalCalibrationError(probabilityTruth),
            selectedCount: selected.count,
            selectedFingerprint: longitudinalFingerprint(selected.sorted()),
            answerPathFingerprint: longitudinalAnswerFingerprint(assessment.answers),
            posteriorFingerprint: longitudinalFingerprint(assessment.thetaPosteriorSnapshot),
            assessableOccurrenceMass: denominator,
            missedOccurrenceMass: missed,
            realizedProjectedCoverage: coverage,
            conservativeCoverageLowerBound: result.diagnostics.conservativeCoverageLowerBound,
            bankA: LongitudinalBankSummary(bankA),
            bankB1: LongitudinalBankSummary(bankB1),
            bankB2: LongitudinalBankSummary(bankB2),
            b1MinusA: bankB1.coverageLowerBound - bankA.coverageLowerBound,
            b2MinusA: bankB2.coverageLowerBound - bankA.coverageLowerBound,
            b2MinusB1: bankB2.coverageLowerBound - bankB1.coverageLowerBound
        )
    )
}

private func longitudinalReplay(
    sourcePath: String,
    destinationPrior: String,
    source: AdaptiveVocabularyAssessment,
    inventory: DocumentVocabularyInventory,
    truths: [String: LongitudinalTruth],
    readerPrior: VocabularyReaderPrior?,
    currentDate: Date,
    target: Double
) -> LongitudinalReplay {
    let replay = AdaptiveVocabularyAssessment(
        inventory: inventory,
        mode: .targetCoverage(target),
        restoredAnswers: source.answers,
        readerPrior: readerPrior,
        currentDate: currentDate
    )
    let result = replay.result()
    let selected = Set(result.items.filter(\.isSelected).map(\.id))
    let included = result.items.filter { $0.classification != .excluded }
    let denominator = included.reduce(0) { $0 + $1.candidate.occurrenceCount }
    let missed = included.reduce(0) { partial, item in
        partial + (truths[item.id]?.known == false && !selected.contains(item.id)
            ? item.candidate.occurrenceCount
            : 0)
    }
    let coverage = denominator == 0 ? 1 : 1 - Double(missed) / Double(denominator)
    return LongitudinalReplay(
        sourcePath: sourcePath,
        destinationPrior: destinationPrior,
        questionCount: source.answeredQuestionCount,
        answerPathFingerprint: longitudinalAnswerFingerprint(source.answers),
        posteriorFingerprint: longitudinalFingerprint(replay.thetaPosteriorSnapshot),
        estimatedTheta: result.diagnostics.estimatedTheta,
        selectedCount: selected.count,
        selectedFingerprint: longitudinalFingerprint(selected.sorted()),
        assessableOccurrenceMass: denominator,
        missedOccurrenceMass: missed,
        realizedProjectedCoverage: coverage,
        conservativeCoverageLowerBound: result.diagnostics.conservativeCoverageLowerBound,
        interpretation: "Conditional on the fixed source question/evidence order and validation metadata; not an authentic destination-prior serving path."
    )
}

private func longitudinalWarmCompatibility(
    coldNatural: LongitudinalPathBuild,
    warmNatural: LongitudinalPathBuild,
    warmFixed: LongitudinalPathBuild,
    inventory: DocumentVocabularyInventory,
    truths: [String: LongitudinalTruth],
    readerPrior: VocabularyReaderPrior?,
    currentDate: Date,
    target: Double
) -> LongitudinalWarmCompatibility {
    let validationOrdinals = [4, 8]
    let applicable = warmNatural.assessment.usedEligibleReaderPrior
    var answerPrefix: [VocabularyAssessmentAnswer] = []
    var validationCount = 0
    var warmLogLikelihood = 0.0
    var coldLogLikelihood = 0.0
    for answer in warmFixed.assessment.answers {
        if applicable,
           answer.wasValidation,
           answer.evidence != .excluded,
           let ordinal = answer.questionOrdinal,
           validationOrdinals.contains(ordinal),
           let warmProbability = answer.predictedKnownBeforeAnswer {
            let coldPrefix = AdaptiveVocabularyAssessment(
                inventory: inventory,
                mode: .targetCoverage(target),
                restoredAnswers: answerPrefix,
                readerPrior: nil,
                currentDate: currentDate
            )
            if let coldProbability = coldPrefix.diagnosticKnownProbability(
                for: answer.canonicalKey
            ) {
                let warmLikelihood = VocabularyObservationModel.evidenceLikelihood(
                    evidence: answer.evidence,
                    latentKnownProbability: warmProbability
                )
                let coldLikelihood = VocabularyObservationModel.evidenceLikelihood(
                    evidence: answer.evidence,
                    latentKnownProbability: coldProbability
                )
                warmLogLikelihood += log(max(warmLikelihood, Double.leastNormalMagnitude))
                coldLogLikelihood += log(max(coldLikelihood, Double.leastNormalMagnitude))
                validationCount += 1
            }
        }
        answerPrefix.append(answer)
        if (answer.questionOrdinal ?? 0) >= (validationOrdinals.last ?? 8) {
            break
        }
    }

    let likelihoodRatio = applicable && validationCount == validationOrdinals.count
        ? warmLogLikelihood - coldLogLikelihood
        : nil
    let supported = likelihoodRatio.map { $0 >= 0 }
    let applyCounterfactual = applicable
        && supported != true
        && warmNatural.assessment.answeredQuestionCount < 20
    let candidateAssessment: AdaptiveVocabularyAssessment
    if applyCounterfactual {
        var prefix: [VocabularyAssessmentAnswer] = []
        var answered = 0
        for answer in warmFixed.assessment.answers {
            prefix.append(answer)
            if answer.evidence != .excluded { answered += 1 }
            if answered >= 20 { break }
        }
        candidateAssessment = AdaptiveVocabularyAssessment(
            inventory: inventory,
            mode: .targetCoverage(target),
            restoredAnswers: prefix,
            readerPrior: readerPrior,
            currentDate: currentDate
        )
    } else {
        candidateAssessment = warmNatural.assessment
    }
    let candidatePath = longitudinalReplay(
        sourcePath: applyCounterfactual
            ? "accumulated-warm-compatibility-minimum-20"
            : "accumulated-warm-natural",
        destinationPrior: "accumulated-warm",
        source: candidateAssessment,
        inventory: inventory,
        truths: truths,
        readerPrior: readerPrior,
        currentDate: currentDate,
        target: target
    )
    let questionReduction = coldNatural.path.questionCount > 0
        ? 1 - Double(candidatePath.questionCount) / Double(coldNatural.path.questionCount)
        : 0
    return LongitudinalWarmCompatibility(
        applicable: applicable,
        validationQuestionOrdinals: validationOrdinals,
        nonExcludedValidationAnswerCount: validationCount,
        warmEvidenceLogLikelihood: applicable ? warmLogLikelihood : nil,
        coldEvidenceLogLikelihood: applicable ? coldLogLikelihood : nil,
        evidenceLogLikelihoodRatio: likelihoodRatio,
        supportsEightQuestionMinimum: supported,
        counterfactualMinimumApplied: applyCounterfactual,
        candidatePath: candidatePath,
        candidateQuestionReduction: questionReduction,
        candidateCoverageDifference: candidatePath.realizedProjectedCoverage
            - coldNatural.path.realizedProjectedCoverage,
        interpretation: "Development-only conditional compatibility signal on identical validation questions/evidence; production stopping remains unchanged."
    )
}

private func longitudinalForensicTrace(
    paths: [(String, AdaptiveVocabularyAssessment)],
    inventory: DocumentVocabularyInventory,
    truths: [String: LongitudinalTruth]
) throws -> LongitudinalForensicTrace {
    let candidates = Dictionary(uniqueKeysWithValues: inventory.candidates.map {
        ($0.canonicalKey, $0)
    })
    let pathTraces = try paths.map { path, assessment -> LongitudinalForensicPath in
        let resultItems = Dictionary(uniqueKeysWithValues: assessment.result().items.map {
            ($0.id, $0)
        })
        let questions = try assessment.answers.enumerated().map { offset, answer in
            guard let candidate = candidates[answer.canonicalKey],
                  let truth = truths[answer.canonicalKey],
                  let item = resultItems[answer.canonicalKey] else {
                throw LongitudinalFailure.missingValue("forensic trace \(path):\(answer.canonicalKey)")
            }
            return LongitudinalForensicQuestion(
                ordinal: answer.questionOrdinal ?? offset + 1,
                canonicalKey: answer.canonicalKey,
                occurrenceCount: candidate.occurrenceCount,
                difficultyMean: candidate.difficultyPrior.mean,
                difficultyStandardDeviation: candidate.difficultyPrior.standardDeviation,
                truthKnown: truth.known,
                learnerItemException: truth.learnerItemException,
                evidence: answer.evidence.rawValue,
                selectionType: answer.selectionType?.rawValue,
                wasValidation: answer.wasValidation,
                predictedKnownBeforeAnswer: answer.predictedKnownBeforeAnswer,
                finalKnownProbability: item.knownProbability,
                finalClassification: item.classification.rawValue,
                selectedInFinalDeck: item.isSelected
            )
        }
        return LongitudinalForensicPath(path: path, questions: questions)
    }
    return LongitudinalForensicTrace(
        paths: pathTraces,
        interpretation: "Selected-case development trace only; hidden truth is synthetic and the case set is outcome-biased."
    )
}

private func recordPrior(
    _ databaseURL: URL,
    contributionID: String,
    assessment: AdaptiveVocabularyAssessment,
    completedAt: Date,
    algorithmVersion: Int
) -> Bool {
    VocabularyReaderPriorStore(databaseURL: databaseURL).recordCompletedSession(
        contributionID: contributionID,
        languageCode: "en",
        thetaPosterior: assessment.thetaPosteriorSnapshot,
        verifiedEvidenceCount: assessment.verifiedEvidenceCount,
        completedAt: completedAt,
        algorithmVersion: algorithmVersion
    )
}

private func loadPrior(_ databaseURL: URL, language: String) -> VocabularyReaderPrior? {
    VocabularyReaderPriorStore(databaseURL: databaseURL).load(languageCode: language)
}

private func completionDate(
    scenario: LongitudinalScenario,
    evaluationDate: Date,
    completedIndex: Int,
    completedCount: Int
) -> Date {
    if scenario == .staleHistory {
        return evaluationDate.addingTimeInterval(-Double(190 + completedCount - completedIndex) * 86_400)
    }
    if scenario == .futureTimestamp {
        return evaluationDate.addingTimeInterval(Double(completedIndex + 1) * 86_400)
    }
    return evaluationDate.addingTimeInterval(-Double(completedCount - completedIndex) * 86_400)
}

private func storedAlgorithmVersion(_ scenario: LongitudinalScenario) -> Int {
    scenario == .incompatibleVersion
        ? VocabularyPreparationSession.currentAlgorithmVersion - 1
        : VocabularyPreparationSession.currentAlgorithmVersion
}

private func clippedNormal(seed: UInt64) -> Double {
    var generator = LongitudinalGenerator(seed: seed)
    return min(5.5, max(-5.5, generator.normal() * 1.4))
}

private func derivedLongitudinalSeed(_ base: UInt64, _ label: String) -> UInt64 {
    var fingerprint = LongitudinalFingerprint()
    fingerprint.mix(base)
    fingerprint.mix(label)
    return UInt64(fingerprint.hex, radix: 16) ?? base
}

private func longitudinalFingerprint(_ values: [Double]) -> String {
    var fingerprint = LongitudinalFingerprint()
    for value in values { fingerprint.mix(value.bitPattern) }
    return fingerprint.hex
}

private func longitudinalFingerprint(_ values: [String]) -> String {
    var fingerprint = LongitudinalFingerprint()
    for value in values { fingerprint.mix(value) }
    return fingerprint.hex
}

private func longitudinalAnswerFingerprint(_ answers: [VocabularyAssessmentAnswer]) -> String {
    var fingerprint = LongitudinalFingerprint()
    for answer in answers {
        fingerprint.mix(answer.canonicalKey)
        fingerprint.mix(answer.evidence.rawValue)
        fingerprint.mix(UInt64(answer.questionOrdinal ?? 0))
        fingerprint.mix(answer.selectionType?.rawValue ?? "none")
        fingerprint.mix(UInt64(answer.wasValidation ? 1 : 0))
    }
    return fingerprint.hex
}

private func longitudinalTruthFingerprint(
    _ truths: [String: LongitudinalTruth],
    inventory: DocumentVocabularyInventory
) -> String {
    var fingerprint = LongitudinalFingerprint()
    for item in inventory.candidates {
        fingerprint.mix(item.canonicalKey)
        fingerprint.mix(UInt64(truths[item.canonicalKey]?.known == true ? 1 : 0))
        fingerprint.mix(UInt64(truths[item.canonicalKey]?.learnerItemException == true ? 1 : 0))
    }
    return fingerprint.hex
}

private func longitudinalResponseFingerprint(
    _ responses: [String: LongitudinalResponse],
    inventory: DocumentVocabularyInventory
) -> String {
    var fingerprint = LongitudinalFingerprint()
    for item in inventory.candidates {
        fingerprint.mix(item.canonicalKey)
        fingerprint.mix(responses[item.canonicalKey]?.evidence.rawValue ?? "missing")
        fingerprint.mix(responses[item.canonicalKey]?.draw.bitPattern ?? 0)
    }
    return fingerprint.hex
}

private func approximatelyEqual(_ lhs: [Double], _ rhs: [Double]) -> Bool {
    lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { abs($0 - $1) < 1e-12 }
}

private func longitudinalMean(_ values: [Double]) -> Double {
    values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
}

private func longitudinalCalibrationError(_ values: [(Double, Bool)]) -> Double {
    guard !values.isEmpty else { return 0 }
    var result = 0.0
    for bin in 0..<10 {
        let lower = Double(bin) / 10
        let upper = Double(bin + 1) / 10
        let entries = values.filter {
            $0.0 >= lower && (bin == 9 ? $0.0 <= upper : $0.0 < upper)
        }
        guard !entries.isEmpty else { continue }
        result += Double(entries.count) / Double(values.count) * abs(
            longitudinalMean(entries.map(\.0))
                - longitudinalMean(entries.map { $0.1 ? 1 : 0 })
        )
    }
    return result
}

private func longitudinalSource() throws -> LongitudinalSource {
    let revision = try longitudinalShell("git rev-parse HEAD")
    let status = try longitudinalShell(
        "git status --short --untracked-files=normal -- Sources Tests scripts Package.swift"
    )
    var statusFingerprint = LongitudinalFingerprint()
    statusFingerprint.mix(status)
    return LongitudinalSource(
        revision: revision,
        dirtyTree: !status.isEmpty,
        dirtyStatusFingerprint: statusFingerprint.hex,
        sourceContentFingerprint: try longitudinalShell(
            "{ git diff --binary -- Sources Tests scripts Package.swift; "
                + "git ls-files --others --exclude-standard -- Sources Tests scripts Package.swift "
                + "| LC_ALL=C sort | while IFS= read -r file; do shasum -a 256 \"$file\"; done; } "
                + "| shasum -a 256 | awk '{print $1}'"
        ),
        swiftVersion: try longitudinalShell("swift --version | head -1"),
        algorithmVersion: VocabularyPreparationSession.currentAlgorithmVersion
    )
}

private func longitudinalMarkdown(_ report: LongitudinalReport) -> String {
    let eligible = report.runs.filter(\.expectedWarmEligibility)
    let meanQuestionReduction = longitudinalMean(eligible.map(\.naturalQuestionReduction))
    let meanNaturalCoverageDifference = longitudinalMean(eligible.map(\.naturalCoverageDifference))
    let adverse = report.runs.filter { $0.naturalCoverageDifference < 0 }.count
    return [
        "# Vocabulary longitudinal warm-start diagnostics — development checkpoint",
        "",
        "Source `\(report.source.revision)`; dirty tree `\(report.source.dirtyTree)`; source fingerprint `\(report.source.sourceContentFingerprint)`.",
        "",
        "This is development-only synthetic evidence through the real isolated SQLite prior store. It is not the historical oracle-informed reference, real-learner calibration, or release acceptance.",
        "",
        "- Runs retained: \(report.runs.count); eligible warm runs: \(eligible.count); ineligible warm runs: \(report.runs.count - eligible.count).",
        String(format: "- Eligible-run mean natural question reduction: %.3f%%.", meanQuestionReduction * 100),
        String(format: "- Eligible-run mean warm-minus-cold realized projected coverage: %.4f percentage points.", meanNaturalCoverageDifference * 100),
        "- Runs with adverse natural warm-minus-cold realized coverage: \(adverse).",
        "- Every evaluation preserves paired hidden truth and potential-response fingerprints across cold, warm, fixed-budget, and replay paths.",
        "- Failed writes, duplicate contributions, abandoned work, reset, insufficient/low-verified/stale/future/incompatible histories remain explicit rather than being promoted to eligible history.",
        "",
        "Interpretation remains scenario- and support-limited. Natural path differences mix prior, stopping, and selection effects; fixed-budget and bidirectional common-evidence replays provide conditional controls rather than unique causal proof.",
        ""
    ].joined(separator: "\n")
}

private func longitudinalMilliseconds(since start: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}

private func longitudinalShell(_ command: String) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-lc", command]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw LongitudinalFailure.command(command) }
    return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func longitudinalSHA256(_ path: String) throws -> String {
    let quoted = "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    return try longitudinalShell("shasum -a 256 \(quoted) | awk '{print $1}'")
}
