import Foundation
import XCTest
@testable import LeafReaderValidation

final class VocabularyLexicalPartitionEvaluatorXCTests: XCTestCase {
    func testPolicyFixtureProducesDeterministicRiskCoverageAndSafetyGate() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/VocabularyLexicalPartition/policy-v1.json")
        let fixtureData = try Data(contentsOf: fixtureURL)

        let first = try evaluateVocabularyLexicalPartitionFixture(fixtureData)
        let second = try evaluateVocabularyLexicalPartitionFixture(fixtureData)
        XCTAssertEqual(first, second)

        let report = try JSONDecoder().decode(
            VocabularyLexicalPartitionEvaluationReport.self,
            from: first
        )
        XCTAssertEqual(report.fixtureID, "lexical-partition-policy-v1")
        XCTAssertEqual(report.metrics.anchorCount, 7)
        XCTAssertEqual(report.metrics.occurrenceCount, 22)
        XCTAssertEqual(report.metrics.resolvedOccurrenceCount, 13)
        XCTAssertEqual(report.metrics.resolvedAnchorCount, 4)
        XCTAssertEqual(report.metrics.predictedSplitCount, 2)
        XCTAssertEqual(report.metrics.correctPredictedSplitCount, 2)
        XCTAssertEqual(report.metrics.splitPrecision, 1)
        XCTAssertEqual(report.metrics.jointLemmaPartOfSpeechAccuracy, 1)
        XCTAssertEqual(report.metrics.b3?.f1, 1)
        XCTAssertEqual(report.metrics.falseSplitPairRate, 0)
        XCTAssertEqual(report.metrics.falseMergePairRate, 0)
        XCTAssertEqual(report.metrics.residualAssignmentAccuracy, 1)
        XCTAssertEqual(report.unavailableNLPSplitCount, 0)

        let wilson = try XCTUnwrap(report.metrics.splitPrecisionWilson95)
        XCTAssertLessThan(wilson.lowerBound, 0.95)
        XCTAssertFalse(report.splitPrecisionGate.passed)
        XCTAssertFalse(report.automaticSplitSafetyGatePassed)

        XCTAssertEqual(
            report.riskCoverageCurve.map(\.minimumSplitOccurrenceSupport),
            [2, 3, 4]
        )
        XCTAssertGreaterThan(
            report.riskCoverageCurve[0].resolvedOccurrenceCoverage,
            report.riskCoverageCurve[1].resolvedOccurrenceCoverage
        )
        XCTAssertGreaterThan(
            report.riskCoverageCurve[1].resolvedOccurrenceCoverage,
            report.riskCoverageCurve[2].resolvedOccurrenceCoverage
        )
        XCTAssertTrue(report.stratifiedMetrics.contains {
            $0.dimension == "nlpAvailability" && $0.value == "unavailable"
        })
        XCTAssertTrue(report.assessmentConsequences.allSatisfy {
            $0.goldOccurrenceDenominator == $0.predictedOccurrenceDenominator
        })
        let englishAssessment = try XCTUnwrap(report.assessmentConsequences.first {
            $0.scope == "language:en"
        })
        XCTAssertEqual(englishAssessment.predictedDirectEvidenceCandidateCount, 8)
        XCTAssertEqual(englishAssessment.predictedCandidateCount, 14)
        let germanAssessment = try XCTUnwrap(report.assessmentConsequences.first {
            $0.scope == "language:de"
        })
        XCTAssertEqual(germanAssessment.predictedDirectEvidenceCandidateCount, 1)
        XCTAssertEqual(germanAssessment.predictedCandidateCount, 1)
    }
}
