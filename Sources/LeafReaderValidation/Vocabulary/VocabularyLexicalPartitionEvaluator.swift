import Foundation
import LeafReaderCore

package struct VocabularyLexicalPartitionOccurrenceResult: Codable, Equatable, Sendable {
    package let occurrenceID: String
    package let goldLexicalKey: String
    package let predictedLexicalKey: String?
    package let isResolved: Bool
    package let isCorrectWhenResolved: Bool
}

package struct VocabularyLexicalPartitionAnchorResult: Codable, Equatable, Sendable {
    package let anchorID: String
    package let languageCode: String
    package let evaluationSplit: String
    package let genre: String
    package let documentFormat: String
    package let nlpAvailability: String
    package let dictionaryAttestationAvailability: String
    package let resolutionState: VocabularyLexicalResolutionState
    package let occurrenceCount: Int
    package let resolvedOccurrenceCount: Int
    package let residualOccurrenceCount: Int
    package let goldClusterCount: Int
    package let predictedClusterCount: Int
    package let occurrences: [VocabularyLexicalPartitionOccurrenceResult]
}

package struct VocabularyLexicalB3Metrics: Codable, Equatable, Sendable {
    package let precision: Double
    package let recall: Double
    package let f1: Double
}

package struct VocabularyWilsonInterval: Codable, Equatable, Sendable {
    package let lowerBound: Double
    package let upperBound: Double
}

package struct VocabularyLexicalPartitionMetrics: Codable, Equatable, Sendable {
    package let anchorCount: Int
    package let occurrenceCount: Int
    package let resolvedOccurrenceCount: Int
    package let resolvedAnchorCount: Int
    package let resolvedOccurrenceCoverage: Double
    package let resolvedAnchorCoverage: Double
    package let ambiguousRate: Double
    package let unresolvedRate: Double
    package let jointLemmaPartOfSpeechAccuracy: Double?
    package let b3: VocabularyLexicalB3Metrics?
    package let predictedSplitCount: Int
    package let correctPredictedSplitCount: Int
    package let splitPrecision: Double?
    package let splitPrecisionWilson95: VocabularyWilsonInterval?
    package let falseSplitPairRate: Double?
    package let falseMergePairRate: Double?
    package let residualAssignmentAccuracy: Double?
}

package struct VocabularyLexicalRiskCoveragePoint: Codable, Equatable, Sendable {
    package let minimumSplitOccurrenceSupport: Int
    package let minimumSplitDistinctContextSupport: Int
    package let resolvedOccurrenceCoverage: Double
    package let resolvedAnchorCoverage: Double
    package let jointErrorRate: Double?
    package let b3F1: Double?
    package let splitPrecision: Double?
}

package struct VocabularyLexicalPartitionStratumMetrics: Codable, Equatable, Sendable {
    package let dimension: String
    package let value: String
    package let metrics: VocabularyLexicalPartitionMetrics
}

package struct VocabularyLexicalPartitionAssessmentConsequence: Codable, Equatable, Sendable {
    package let scope: String
    package let languageCode: String
    package let goldCandidateCount: Int
    package let predictedCandidateCount: Int
    package let predictedDirectEvidenceCandidateCount: Int
    package let goldOccurrenceDenominator: Int
    package let predictedOccurrenceDenominator: Int
    package let firstQuestionChanged: Bool
    package let goldQuestionPath: [String]
    package let predictedQuestionPath: [String]
    package let questionPathMismatchCount: Int
    package let thetaPosteriorJensenShannonDivergence: Double
    package let expectedCurrentCoverageDelta: Double
    package let expectedCoverageAfterSelectionDelta: Double
    package let selectedDeckSymmetricDifferenceCount: Int
}

package struct VocabularyLexicalSplitPrecisionGate: Codable, Equatable, Sendable {
    package let pointEstimateTarget: Double
    package let wilsonLowerBoundTarget: Double
    package let predictedSplitCount: Int
    package let correctPredictedSplitCount: Int
    package let pointEstimate: Double?
    package let wilson95: VocabularyWilsonInterval?
    package let passed: Bool
}

package struct VocabularyLexicalPartitionEvaluationReport: Codable, Equatable, Sendable {
    package let schemaVersion: Int
    package let fixtureID: String
    package let fixtureRelease: String
    package let reconcilerVersion: String
    package let anchorResults: [VocabularyLexicalPartitionAnchorResult]
    package let metrics: VocabularyLexicalPartitionMetrics
    package let riskCoverageCurve: [VocabularyLexicalRiskCoveragePoint]
    package let stratifiedMetrics: [VocabularyLexicalPartitionStratumMetrics]
    package let assessmentConsequences: [VocabularyLexicalPartitionAssessmentConsequence]
    package let splitPrecisionGate: VocabularyLexicalSplitPrecisionGate
    package let unavailableNLPSplitCount: Int
    package let automaticSplitSafetyGatePassed: Bool
    package let limitations: [String]
}

private struct LexicalPartitionFixture: Decodable {
    let schemaVersion: Int
    let fixtureID: String
    let release: String
    let supportThresholds: [Int]?
    let anchors: [Anchor]

    struct Anchor: Decodable {
        let anchorID: String
        let languageCode: String
        let evaluationSplit: String
        let genre: String
        let documentFormat: String
        let nlpAvailability: String
        let dictionaryAttestationAvailability: String
        let anchor: AnchorBasis
        let attributes: [String: String]?
        let occurrences: [Occurrence]
    }

    struct AnchorBasis: Decodable {
        enum Kind: String, Decodable {
            case resolvedLemma
            case exactSurface
        }

        let kind: Kind
        let value: String
    }

    struct Occurrence: Decodable {
        let occurrenceID: String
        let surface: String
        let goldLemma: String
        let goldPartOfSpeech: VocabularyPartOfSpeech
        let contextFingerprint: String
        let analyses: [Analysis]
    }

    struct Analysis: Decodable {
        let lemma: String
        let partOfSpeech: VocabularyPartOfSpeech
        let source: VocabularyLinguisticEvidenceSource
        let rawScore: Double?
        let confidence: VocabularyEvidenceConfidence
    }
}

private struct EvaluatedAnchor {
    let fixture: LexicalPartitionFixture.Anchor
    let anchor: VocabularyLexicalAnchorID
    let result: VocabularyLexicalPartitionAnchorResult
    let lexicalItemByKey: [String: VocabularyLexicalItemID]
}

private struct CandidateSeed {
    let key: String
    let lemma: String
    let lexicalItemID: VocabularyLexicalItemID?
    let partOfSpeech: VocabularyPartOfSpeech
    let identityPolicy: VocabularyAssessmentIdentityPolicy
    var occurrenceCount: Int
}

private struct AssessmentTrace {
    let questionPath: [String]
    let thetaPosterior: [Double]
    let expectedCurrentCoverage: Double
    let expectedCoverageAfterSelection: Double
    let selectedKeys: Set<String>
}

package func evaluateVocabularyLexicalPartitionFixture(_ fixtureData: Data) throws -> Data {
    let fixture = try JSONDecoder().decode(LexicalPartitionFixture.self, from: fixtureData)
    guard fixture.schemaVersion == 1,
          !fixture.fixtureID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !fixture.anchors.isEmpty else {
        throw CocoaError(.coderReadCorrupt)
    }

    let productionConfiguration = VocabularyLexicalReconciler.Configuration.production
    let evaluated = try evaluate(
        anchors: fixture.anchors,
        configuration: productionConfiguration
    )
    let overallMetrics = metrics(for: evaluated)
    let splitGate = splitPrecisionGate(overallMetrics)
    let unavailableNLPSplitCount = evaluated.filter {
        $0.result.resolutionState == .resolvedSplit
            && $0.fixture.nlpAvailability.caseInsensitiveCompare("unavailable") == .orderedSame
    }.count
    let thresholds = Array(Set((fixture.supportThresholds ?? [2, 3, 4]).map { max(2, $0) })).sorted()
    let riskCoverage = try thresholds.map { threshold -> VocabularyLexicalRiskCoveragePoint in
        let pointEvaluated = try evaluate(
            anchors: fixture.anchors,
            configuration: VocabularyLexicalReconciler.Configuration(
                minimumSplitOccurrenceSupport: threshold,
                minimumSplitDistinctContextSupport: threshold
            )
        )
        let pointMetrics = metrics(for: pointEvaluated)
        return VocabularyLexicalRiskCoveragePoint(
            minimumSplitOccurrenceSupport: threshold,
            minimumSplitDistinctContextSupport: threshold,
            resolvedOccurrenceCoverage: pointMetrics.resolvedOccurrenceCoverage,
            resolvedAnchorCoverage: pointMetrics.resolvedAnchorCoverage,
            jointErrorRate: pointMetrics.jointLemmaPartOfSpeechAccuracy.map { 1 - $0 },
            b3F1: pointMetrics.b3?.f1,
            splitPrecision: pointMetrics.splitPrecision
        )
    }

    let report = VocabularyLexicalPartitionEvaluationReport(
        schemaVersion: 1,
        fixtureID: fixture.fixtureID,
        fixtureRelease: fixture.release,
        reconcilerVersion: VocabularyLexicalReconciler.policyVersion,
        anchorResults: evaluated.map(\.result),
        metrics: overallMetrics,
        riskCoverageCurve: riskCoverage,
        stratifiedMetrics: stratifiedMetrics(evaluated),
        assessmentConsequences: assessmentConsequences(evaluated),
        splitPrecisionGate: splitGate,
        unavailableNLPSplitCount: unavailableNLPSplitCount,
        automaticSplitSafetyGatePassed: splitGate.passed && unavailableNLPSplitCount == 0,
        limitations: [
            "This fixture validates deterministic reconciliation and partition metrics; it is not representative reading-document evidence.",
            "The split-precision safety gate is necessary but is not sufficient for production activation; ADR-0001 also requires held-out document, cross-format, runtime, assessment-stability, graceful-degradation, and performance evidence.",
            "The risk-coverage series varies structural corroboration support. It must not be interpreted as a calibrated probability curve."
        ]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(report)
}

private func evaluate(
    anchors: [LexicalPartitionFixture.Anchor],
    configuration: VocabularyLexicalReconciler.Configuration
) throws -> [EvaluatedAnchor] {
    let reconciler = VocabularyLexicalReconciler(configuration: configuration)
    return try anchors.map { fixtureAnchor in
        guard !fixtureAnchor.anchorID.isEmpty,
              !fixtureAnchor.languageCode.isEmpty,
              !fixtureAnchor.occurrences.isEmpty else {
            throw CocoaError(.coderReadCorrupt)
        }
        let anchor: VocabularyLexicalAnchorID
        switch fixtureAnchor.anchor.kind {
        case .resolvedLemma:
            anchor = VocabularyLexicalAnchorID(
                language: fixtureAnchor.languageCode,
                basis: .resolvedLemma(fixtureAnchor.anchor.value)
            )
        case .exactSurface:
            anchor = VocabularyLexicalAnchorID(
                language: fixtureAnchor.languageCode,
                basis: .exactSurface(fixtureAnchor.anchor.value)
            )
        }

        var coreIDByFixtureID: [String: VocabularyOccurrenceAnalysisID] = [:]
        var fixtureIDByCoreID: [VocabularyOccurrenceAnalysisID: String] = [:]
        var seenFixtureIDs = Set<String>()
        let analyses = try fixtureAnchor.occurrences.enumerated().map { index, fixtureOccurrence in
            guard !fixtureOccurrence.occurrenceID.isEmpty,
                  seenFixtureIDs.insert(fixtureOccurrence.occurrenceID).inserted else {
                throw CocoaError(.coderReadCorrupt)
            }
            let coreID = VocabularyOccurrenceAnalysisID(
                unitIndex: index,
                utf16Location: 0,
                utf16Length: fixtureOccurrence.surface.utf16.count
            )
            coreIDByFixtureID[fixtureOccurrence.occurrenceID] = coreID
            fixtureIDByCoreID[coreID] = fixtureOccurrence.occurrenceID
            return VocabularyOccurrenceAnalysis(
                occurrenceID: coreID,
                sourceRange: VocabularyDocumentSourceRange(
                    unitIndex: index,
                    utf16Location: 0,
                    utf16Length: fixtureOccurrence.surface.utf16.count
                ),
                surface: fixtureOccurrence.surface,
                anchor: anchor,
                analyses: fixtureOccurrence.analyses.map {
                    VocabularyMorphologicalAnalysis(
                        lemma: $0.lemma,
                        partOfSpeech: $0.partOfSpeech,
                        source: $0.source,
                        rawScore: $0.rawScore,
                        confidence: $0.confidence
                    )
                },
                contextFingerprint: fixtureOccurrence.contextFingerprint
            )
        }

        let resolution = reconciler.reconcile(anchor: anchor, occurrences: analyses)
        var predictedKeyByCoreID: [VocabularyOccurrenceAnalysisID: String] = [:]
        var lexicalItemByKey: [String: VocabularyLexicalItemID] = [:]
        switch resolution {
        case let .resolvedSingle(group):
            lexicalItemByKey[group.lexicalItemID.canonicalKey] = group.lexicalItemID
            for occurrenceID in group.assignedOccurrenceIDs {
                predictedKeyByCoreID[occurrenceID] = group.lexicalItemID.canonicalKey
            }
        case let .resolvedSplit(partition):
            for child in partition.children {
                lexicalItemByKey[child.lexicalItemID.canonicalKey] = child.lexicalItemID
                for occurrenceID in child.assignedOccurrenceIDs {
                    predictedKeyByCoreID[occurrenceID] = child.lexicalItemID.canonicalKey
                }
            }
        case .ambiguous, .unresolved:
            break
        }

        let occurrenceResults = fixtureAnchor.occurrences.map { fixtureOccurrence in
            let gold = VocabularyLexicalItemID(
                language: fixtureAnchor.languageCode,
                lemma: fixtureOccurrence.goldLemma,
                partOfSpeech: fixtureOccurrence.goldPartOfSpeech
            ).canonicalKey
            let coreID = coreIDByFixtureID[fixtureOccurrence.occurrenceID]
            let predicted = coreID.flatMap { predictedKeyByCoreID[$0] }
            return VocabularyLexicalPartitionOccurrenceResult(
                occurrenceID: fixtureOccurrence.occurrenceID,
                goldLexicalKey: gold,
                predictedLexicalKey: predicted,
                isResolved: predicted != nil,
                isCorrectWhenResolved: predicted == gold
            )
        }
        let goldClusters = Set(occurrenceResults.map(\.goldLexicalKey))
        let predictedClusters = Set(occurrenceResults.compactMap(\.predictedLexicalKey))
        return EvaluatedAnchor(
            fixture: fixtureAnchor,
            anchor: anchor,
            result: VocabularyLexicalPartitionAnchorResult(
                anchorID: fixtureAnchor.anchorID,
                languageCode: fixtureAnchor.languageCode,
                evaluationSplit: fixtureAnchor.evaluationSplit,
                genre: fixtureAnchor.genre,
                documentFormat: fixtureAnchor.documentFormat,
                nlpAvailability: fixtureAnchor.nlpAvailability,
                dictionaryAttestationAvailability: fixtureAnchor.dictionaryAttestationAvailability,
                resolutionState: resolution.state,
                occurrenceCount: occurrenceResults.count,
                resolvedOccurrenceCount: occurrenceResults.filter(\.isResolved).count,
                residualOccurrenceCount: resolution.diagnostics.residualOccurrenceCount,
                goldClusterCount: goldClusters.count,
                predictedClusterCount: predictedClusters.count,
                occurrences: occurrenceResults
            ),
            lexicalItemByKey: lexicalItemByKey
        )
    }
}

private func metrics(for evaluated: [EvaluatedAnchor]) -> VocabularyLexicalPartitionMetrics {
    let anchors = evaluated.map(\.result)
    let occurrences = anchors.flatMap(\.occurrences)
    let resolved = occurrences.filter(\.isResolved)
    let resolvedAnchorCount = anchors.filter {
        $0.resolutionState == .resolvedSingle || $0.resolutionState == .resolvedSplit
    }.count
    let ambiguousCount = anchors.filter { $0.resolutionState == .ambiguous }.count
    let unresolvedCount = anchors.filter { $0.resolutionState == .unresolved }.count
    let predictedSplits = anchors.filter { $0.resolutionState == .resolvedSplit }
    let correctPredictedSplits = predictedSplits.filter { $0.goldClusterCount > 1 }

    let sameGoldPairResult = pairRate(resolved, whereGoldMatches: true)
    let differentGoldPairResult = pairRate(resolved, whereGoldMatches: false)
    let residualAccuracyPopulation = anchors.filter {
        $0.resolutionState == .resolvedSplit && $0.goldClusterCount > 1
    }.flatMap(\.occurrences).filter(\.isResolved)
    let splitPrecision = ratio(correctPredictedSplits.count, predictedSplits.count)

    return VocabularyLexicalPartitionMetrics(
        anchorCount: anchors.count,
        occurrenceCount: occurrences.count,
        resolvedOccurrenceCount: resolved.count,
        resolvedAnchorCount: resolvedAnchorCount,
        resolvedOccurrenceCoverage: ratioOrZero(resolved.count, occurrences.count),
        resolvedAnchorCoverage: ratioOrZero(resolvedAnchorCount, anchors.count),
        ambiguousRate: ratioOrZero(ambiguousCount, anchors.count),
        unresolvedRate: ratioOrZero(unresolvedCount, anchors.count),
        jointLemmaPartOfSpeechAccuracy: ratio(
            resolved.filter(\.isCorrectWhenResolved).count,
            resolved.count
        ),
        b3: b3Metrics(resolved),
        predictedSplitCount: predictedSplits.count,
        correctPredictedSplitCount: correctPredictedSplits.count,
        splitPrecision: splitPrecision,
        splitPrecisionWilson95: splitPrecision.map { _ in
            wilson95(successes: correctPredictedSplits.count, total: predictedSplits.count)
        },
        falseSplitPairRate: sameGoldPairResult,
        falseMergePairRate: differentGoldPairResult,
        residualAssignmentAccuracy: ratio(
            residualAccuracyPopulation.filter(\.isCorrectWhenResolved).count,
            residualAccuracyPopulation.count
        )
    )
}

private func b3Metrics(
    _ resolved: [VocabularyLexicalPartitionOccurrenceResult]
) -> VocabularyLexicalB3Metrics? {
    guard !resolved.isEmpty else { return nil }
    let predicted = Dictionary(grouping: resolved) { $0.predictedLexicalKey ?? "" }
    let gold = Dictionary(grouping: resolved, by: \.goldLexicalKey)
    var precision = 0.0
    var recall = 0.0
    for occurrence in resolved {
        guard let predictedKey = occurrence.predictedLexicalKey,
              let predictedCluster = predicted[predictedKey],
              let goldCluster = gold[occurrence.goldLexicalKey] else {
            continue
        }
        let intersection = predictedCluster.filter {
            $0.goldLexicalKey == occurrence.goldLexicalKey
        }.count
        precision += Double(intersection) / Double(predictedCluster.count)
        recall += Double(intersection) / Double(goldCluster.count)
    }
    precision /= Double(resolved.count)
    recall /= Double(resolved.count)
    let f1 = precision + recall > 0 ? 2 * precision * recall / (precision + recall) : 0
    return VocabularyLexicalB3Metrics(precision: precision, recall: recall, f1: f1)
}

private func pairRate(
    _ resolved: [VocabularyLexicalPartitionOccurrenceResult],
    whereGoldMatches: Bool
) -> Double? {
    guard resolved.count >= 2 else { return nil }
    var denominator = 0
    var errors = 0
    for leftIndex in 0..<(resolved.count - 1) {
        for rightIndex in (leftIndex + 1)..<resolved.count {
            let left = resolved[leftIndex]
            let right = resolved[rightIndex]
            let sameGold = left.goldLexicalKey == right.goldLexicalKey
            guard sameGold == whereGoldMatches else { continue }
            denominator += 1
            let samePredicted = left.predictedLexicalKey == right.predictedLexicalKey
            if whereGoldMatches ? !samePredicted : samePredicted {
                errors += 1
            }
        }
    }
    return ratio(errors, denominator)
}

private func wilson95(successes: Int, total: Int) -> VocabularyWilsonInterval {
    precondition(total > 0 && successes >= 0 && successes <= total)
    let z = 1.959_963_984_540_054
    let n = Double(total)
    let p = Double(successes) / n
    let zSquared = z * z
    let denominator = 1 + zSquared / n
    let center = (p + zSquared / (2 * n)) / denominator
    let margin = z * sqrt((p * (1 - p) + zSquared / (4 * n)) / n) / denominator
    return VocabularyWilsonInterval(
        lowerBound: max(0, center - margin),
        upperBound: min(1, center + margin)
    )
}

private func splitPrecisionGate(
    _ metrics: VocabularyLexicalPartitionMetrics
) -> VocabularyLexicalSplitPrecisionGate {
    let pointTarget = 0.98
    let lowerTarget = 0.95
    let point = metrics.splitPrecision
    let interval = metrics.splitPrecisionWilson95
    return VocabularyLexicalSplitPrecisionGate(
        pointEstimateTarget: pointTarget,
        wilsonLowerBoundTarget: lowerTarget,
        predictedSplitCount: metrics.predictedSplitCount,
        correctPredictedSplitCount: metrics.correctPredictedSplitCount,
        pointEstimate: point,
        wilson95: interval,
        passed: (point ?? 0) >= pointTarget && (interval?.lowerBound ?? 0) >= lowerTarget
    )
}

private func stratifiedMetrics(
    _ evaluated: [EvaluatedAnchor]
) -> [VocabularyLexicalPartitionStratumMetrics] {
    var groups: [String: (dimension: String, value: String, anchors: [EvaluatedAnchor])] = [:]
    for anchor in evaluated {
        var dimensions: [(String, String)] = [
            ("language", anchor.fixture.languageCode),
            ("evaluationSplit", anchor.fixture.evaluationSplit),
            ("genre", anchor.fixture.genre),
            ("documentFormat", anchor.fixture.documentFormat),
            ("nlpAvailability", anchor.fixture.nlpAvailability),
            ("dictionaryAttestationAvailability", anchor.fixture.dictionaryAttestationAvailability),
            ("goldPartition", anchor.result.goldClusterCount > 1 ? "multi" : "single"),
            ("goldPartOfSpeechSet", Set(anchor.result.occurrences.map {
                lexicalPartOfSpeech(from: $0.goldLexicalKey)
            }).sorted().joined(separator: "+")),
            ("occurrenceCountBand", occurrenceCountBand(anchor.result.occurrenceCount))
        ]
        dimensions.append(contentsOf: (anchor.fixture.attributes ?? [:]).map {
            ("attribute.\($0.key)", $0.value)
        })
        for (dimension, value) in dimensions {
            let key = "\(dimension)\u{1F}\(value)"
            if var existing = groups[key] {
                existing.anchors.append(anchor)
                groups[key] = existing
            } else {
                groups[key] = (dimension, value, [anchor])
            }
        }
    }
    return groups.values.map {
        VocabularyLexicalPartitionStratumMetrics(
            dimension: $0.dimension,
            value: $0.value,
            metrics: metrics(for: $0.anchors)
        )
    }.sorted {
        if $0.dimension != $1.dimension { return $0.dimension < $1.dimension }
        return $0.value < $1.value
    }
}

private func assessmentConsequences(
    _ evaluated: [EvaluatedAnchor]
) -> [VocabularyLexicalPartitionAssessmentConsequence] {
    let languages = Set(evaluated.map { $0.fixture.languageCode })
    var scopes: [(String, String, [EvaluatedAnchor])] = []
    for language in languages.sorted() {
        let languageAnchors = evaluated.filter { $0.fixture.languageCode == language }
        scopes.append(("language:\(language)", language, languageAnchors))
        for split in Set(languageAnchors.map { $0.fixture.evaluationSplit }).sorted() {
            scopes.append((
                "language:\(language)|split:\(split)",
                language,
                languageAnchors.filter { $0.fixture.evaluationSplit == split }
            ))
        }
    }
    return scopes.map { scope, language, anchors in
        let gold = candidates(for: anchors, predicted: false)
        let predicted = candidates(for: anchors, predicted: true)
        let goldTrace = assessmentTrace(candidates: gold, languageCode: language)
        let predictedTrace = assessmentTrace(candidates: predicted, languageCode: language)
        return VocabularyLexicalPartitionAssessmentConsequence(
            scope: scope,
            languageCode: language,
            goldCandidateCount: gold.count,
            predictedCandidateCount: predicted.count,
            predictedDirectEvidenceCandidateCount: predicted.filter {
                $0.identityPolicy == .directEvidenceOnly
            }.count,
            goldOccurrenceDenominator: gold.reduce(0) { $0 + $1.occurrenceCount },
            predictedOccurrenceDenominator: predicted.reduce(0) { $0 + $1.occurrenceCount },
            firstQuestionChanged: goldTrace.questionPath.first != predictedTrace.questionPath.first,
            goldQuestionPath: goldTrace.questionPath,
            predictedQuestionPath: predictedTrace.questionPath,
            questionPathMismatchCount: questionPathMismatchCount(
                goldTrace.questionPath,
                predictedTrace.questionPath
            ),
            thetaPosteriorJensenShannonDivergence: jensenShannon(
                goldTrace.thetaPosterior,
                predictedTrace.thetaPosterior
            ),
            expectedCurrentCoverageDelta:
                predictedTrace.expectedCurrentCoverage - goldTrace.expectedCurrentCoverage,
            expectedCoverageAfterSelectionDelta:
                predictedTrace.expectedCoverageAfterSelection - goldTrace.expectedCoverageAfterSelection,
            selectedDeckSymmetricDifferenceCount:
                goldTrace.selectedKeys.symmetricDifference(predictedTrace.selectedKeys).count
        )
    }
}

private func candidates(
    for evaluated: [EvaluatedAnchor],
    predicted: Bool
) -> [DocumentVocabularyCandidate] {
    var seeds: [String: CandidateSeed] = [:]
    for anchor in evaluated {
        for occurrence in anchor.result.occurrences {
            let key: String
            let lexicalItemID: VocabularyLexicalItemID?
            let partOfSpeech: VocabularyPartOfSpeech
            let policy: VocabularyAssessmentIdentityPolicy
            let lemma: String
            if predicted, let predictedKey = occurrence.predictedLexicalKey,
               let item = anchor.lexicalItemByKey[predictedKey] {
                key = predictedKey
                lexicalItemID = item
                partOfSpeech = item.partOfSpeech
                policy = .fullInference
                lemma = item.lemma
            } else if predicted {
                let isResidual = anchor.result.resolutionState == .resolvedSingle
                    || anchor.result.resolutionState == .resolvedSplit
                key = anchor.anchor.canonicalKey + (isResidual ? "|residual" : "")
                lexicalItemID = nil
                partOfSpeech = .unknown
                policy = .directEvidenceOnly
                lemma = anchor.anchor.displayValue
            } else {
                key = occurrence.goldLexicalKey
                let fixtureOccurrence = anchor.fixture.occurrences.first {
                    $0.occurrenceID == occurrence.occurrenceID
                }
                let goldLemma = fixtureOccurrence?.goldLemma ?? anchor.anchor.displayValue
                let goldPart = fixtureOccurrence?.goldPartOfSpeech ?? .unknown
                lexicalItemID = VocabularyLexicalItemID(
                    language: anchor.fixture.languageCode,
                    lemma: goldLemma,
                    partOfSpeech: goldPart
                )
                partOfSpeech = goldPart
                policy = .fullInference
                lemma = goldLemma
            }
            if var seed = seeds[key] {
                seed.occurrenceCount += 1
                seeds[key] = seed
            } else {
                seeds[key] = CandidateSeed(
                    key: key,
                    lemma: lemma,
                    lexicalItemID: lexicalItemID,
                    partOfSpeech: partOfSpeech,
                    identityPolicy: policy,
                    occurrenceCount: 1
                )
            }
        }
    }
    return seeds.values.sorted { $0.key < $1.key }.enumerated().map { index, seed in
        DocumentVocabularyCandidate(
            canonicalKey: seed.key,
            displayLemma: seed.lemma,
            lexicalItemID: seed.lexicalItemID,
            partOfSpeech: seed.partOfSpeech,
            identityPolicy: seed.identityPolicy,
            observedForms: [
                VocabularyDocumentObservedForm(
                    surface: seed.lemma,
                    occurrenceCount: seed.occurrenceCount
                )
            ],
            occurrenceCount: seed.occurrenceCount,
            representativeRange: VocabularyDocumentSourceRange(
                unitIndex: index,
                utf16Location: 0,
                utf16Length: seed.lemma.utf16.count
            ),
            generalFrequencyRank: nil,
            difficulty: 0
        )
    }
}

private func assessmentTrace(
    candidates: [DocumentVocabularyCandidate],
    languageCode: String
) -> AssessmentTrace {
    var assessment = AdaptiveVocabularyAssessment(
        inventory: DocumentVocabularyInventory(
            languageCode: languageCode,
            candidates: candidates
        ),
        mode: .targetCoverage(0.98),
        algorithmVersion: VocabularyPreparationSession.lexicalReconciliationAlgorithmVersion
    )
    var path: [String] = []
    while path.count < 5, !assessment.isFinished, let question = assessment.nextQuestion() {
        path.append(question.canonicalKey)
        assessment.record(.reportedUnknown, for: question.canonicalKey)
    }
    let result = assessment.result()
    return AssessmentTrace(
        questionPath: path,
        thetaPosterior: assessment.thetaPosteriorSnapshot,
        expectedCurrentCoverage: result.expectedCurrentCoverage,
        expectedCoverageAfterSelection: result.expectedCoverageAfterSelection,
        selectedKeys: Set(result.items.filter(\.isSelected).map(\.id))
    )
}

private func jensenShannon(_ lhs: [Double], _ rhs: [Double]) -> Double {
    guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
    var divergence = 0.0
    for index in lhs.indices {
        let p = max(0, lhs[index])
        let q = max(0, rhs[index])
        let midpoint = (p + q) / 2
        guard midpoint > 0 else { continue }
        if p > 0 { divergence += 0.5 * p * log(p / midpoint) }
        if q > 0 { divergence += 0.5 * q * log(q / midpoint) }
    }
    return divergence
}

private func questionPathMismatchCount(_ lhs: [String], _ rhs: [String]) -> Int {
    let shared = min(lhs.count, rhs.count)
    return zip(lhs.prefix(shared), rhs.prefix(shared)).filter(!=).count
        + abs(lhs.count - rhs.count)
}

private func lexicalPartOfSpeech(from canonicalKey: String) -> String {
    let parts = canonicalKey.split(separator: "|", omittingEmptySubsequences: false)
    guard parts.count >= 3 else { return "unknown" }
    return String(parts[2])
}

private func occurrenceCountBand(_ count: Int) -> String {
    switch count {
    case ...1: "1"
    case 2...3: "2-3"
    case 4...7: "4-7"
    default: "8+"
    }
}

private func ratio(_ numerator: Int, _ denominator: Int) -> Double? {
    guard denominator > 0 else { return nil }
    return Double(numerator) / Double(denominator)
}

private func ratioOrZero(_ numerator: Int, _ denominator: Int) -> Double {
    ratio(numerator, denominator) ?? 0
}
