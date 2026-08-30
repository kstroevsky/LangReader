import XCTest
import LeafReaderCore

final class VocabularyMeasurementModelsXCTests: XCTestCase {
    func testAssessmentModelConfigurationKeepsProductionDefaultsExplicit() {
        let configuration = VocabularyAssessmentModelConfiguration.production

        XCTAssertEqual(configuration.evidenceReliabilityScale, 1)
        XCTAssertEqual(configuration.minimumEpsilonKnowledge, 0.05)
        XCTAssertEqual(configuration.coverageQuantile, 0.05)
        XCTAssertEqual(configuration.warmPriorWeight, 0.90)
        XCTAssertEqual(configuration.coverageStoppingComputation, .staged)
    }

    func testKnowledgeModelPreservesLockedRaschMathematics() {
        let theta = 1.25
        let difficulty = -0.40
        let epsilonKnowledge = 0.05
        let base = 1 / (1 + exp(-(theta - difficulty)))
        let expected = epsilonKnowledge + (1 - 2 * epsilonKnowledge) * base

        XCTAssertEqual(
            VocabularyKnowledgeModel.knownProbability(
                theta: theta,
                difficulty: difficulty,
                epsilonKnowledge: epsilonKnowledge
            ),
            expected,
            accuracy: 1e-12
        )
    }

    func testObservationReliabilityIsIndependentOfKnowledgeMismatch() throws {
        let emission = try XCTUnwrap(
            VocabularyObservationModel.emission(for: .verifiedKnown)
        )
        XCTAssertEqual(emission.reliability, 0.97)
        XCTAssertEqual(emission.probabilityGivenKnown, 0.97)
        XCTAssertEqual(emission.probabilityGivenUnknown, 0.03, accuracy: 1e-12)

        let latentKnown = VocabularyKnowledgeModel.adjustedKnownProbability(
            baseKnownProbability: 0.80,
            epsilonKnowledge: 0.25
        )
        let expected = 0.97 * latentKnown + 0.03 * (1 - latentKnown)
        let formerlyCapped = 0.75 * latentKnown + 0.25 * (1 - latentKnown)
        let actual = VocabularyObservationModel.evidenceLikelihood(
            evidence: .verifiedKnown,
            latentKnownProbability: latentKnown
        )

        XCTAssertEqual(actual, expected, accuracy: 1e-12)
        XCTAssertNotEqual(actual, formerlyCapped, accuracy: 1e-6)
    }

    func testDiagnosticReliabilityScaleChangesOnlyObservationEmission() throws {
        let emission = try XCTUnwrap(
            VocabularyObservationModel.emission(
                for: .verifiedKnown,
                reliabilityScale: 0.8
            )
        )

        XCTAssertEqual(emission.reliability, 0.876, accuracy: 1e-12)
        XCTAssertEqual(
            VocabularyKnowledgeModel.knownProbability(
                theta: 0.7,
                difficulty: -0.2,
                epsilonKnowledge: 0.05
            ),
            0.05 + 0.9 / (1 + exp(-0.9)),
            accuracy: 1e-12
        )
    }

    func testAnsweredPosteriorUsesTheSameObservationEmission() {
        let prior = 0.40
        let expectedKnownJoint = prior * 0.05
        let expectedUnknownJoint = (1 - prior) * 0.95
        let expected = expectedKnownJoint / (expectedKnownJoint + expectedUnknownJoint)

        XCTAssertEqual(
            VocabularyObservationModel.posteriorKnownProbability(
                prior: prior,
                evidence: .reportedUnknown
            ),
            expected,
            accuracy: 1e-12
        )
    }

    func testObservationManifestIsVersionedAndEveryGoldenUsesCoreModels() throws {
        let manifest = VocabularyObservationModel.manifest()

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.observationModelVersion, VocabularyObservationModel.version)
        XCTAssertEqual(manifest.knowledgeModelVersion, VocabularyKnowledgeModel.version)
        XCTAssertEqual(manifest.reliabilitySourceVersion, VocabularyObservationModel.reliabilitySourceVersion)
        XCTAssertEqual(
            Set(manifest.evidence.map(\.evidence)),
            Set(VocabularyKnowledgeEvidence.allCases.filter { $0 != .excluded })
        )

        for fixture in manifest.goldenFixtures {
            let latentKnown = VocabularyKnowledgeModel.knownProbability(
                theta: fixture.theta,
                difficulty: fixture.difficulty,
                epsilonKnowledge: fixture.epsilonKnowledge
            )
            XCTAssertEqual(latentKnown, fixture.latentKnownProbability, accuracy: 1e-12)
            XCTAssertEqual(
                VocabularyObservationModel.evidenceLikelihood(
                    evidence: fixture.evidence,
                    latentKnownProbability: latentKnown
                ),
                fixture.evidenceLikelihood,
                accuracy: 1e-12
            )
            XCTAssertEqual(
                VocabularyObservationModel.posteriorKnownProbability(
                    prior: latentKnown,
                    evidence: fixture.evidence
                ),
                fixture.posteriorKnownProbability,
                accuracy: 1e-12
            )
        }
    }
}
