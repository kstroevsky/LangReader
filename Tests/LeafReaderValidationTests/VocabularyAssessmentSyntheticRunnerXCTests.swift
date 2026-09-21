import LeafReaderCore
import XCTest
@testable import LeafReaderValidation

final class VocabularyAssessmentSyntheticRunnerXCTests: XCTestCase {
    func testSmallDevelopmentRunnerMatchesFrozenSemanticFixture() throws {
        let request = VocabularyAssessmentEvaluationRequest(
            seed: 42,
            readers: 1,
            lemmas: 20,
            documents: 1,
            itemResidualStandardDeviation: 0.8,
            responseNoiseRate: 0.12,
            idiosyncraticFlipRate: 0.12,
            evidenceReliabilityScale: 1,
            minimumEpsilonKnowledge: 0.05,
            difficultyPriorStandardDeviationScale: 1,
            coverageQuantile: 0.05,
            warmPriorWeight: 0.90,
            coverageStoppingComputation: "full-every-answer",
            adaptiveLossPopulation: .allNonExcluded,
            questionObjective: .evidenceSurrogate,
            usesPairedDiagnosticSubstreams: false
        )
        let first = try runVocabularyAssessmentEvaluation(request)
        let second = try runVocabularyAssessmentEvaluation(request)
        XCTAssertEqual(first.jsonData, second.jsonData)
        XCTAssertEqual(first.markdown, second.markdown)
        XCTAssertFalse(first.eligible)
        XCTAssertFalse(first.passed)
        XCTAssertEqual(
            VocabularyDiagnosticArtifacts.sha256(of: first.jsonData),
            "ed73e2807e321340f911755b9266c61f26b0e547e0548dc9bd444304eff08016"
        )
        XCTAssertTrue(first.markdown.contains("Quality gates: FAIL."))
    }
}
