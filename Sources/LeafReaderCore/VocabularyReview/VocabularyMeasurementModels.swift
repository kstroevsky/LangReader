import Foundation

/// The versioned latent-knowledge curve used by vocabulary assessment.
///
/// `epsilonKnowledge` models person-item exceptions and other mismatch that a
/// one-dimensional Rasch curve cannot explain. It is intentionally independent
/// from the reliability of the response protocol used to observe that knowledge.
package enum VocabularyKnowledgeModel {
    package static let version = "rasch-knowledge-v1"
    package static let defaultEpsilonKnowledge = 0.05

    package static func baseKnownProbability(theta: Double, difficulty: Double) -> Double {
        1 / (1 + exp(-(theta - difficulty)))
    }

    package static func adjustedKnownProbability(
        baseKnownProbability: Double,
        epsilonKnowledge: Double
    ) -> Double {
        epsilonKnowledge + (1 - 2 * epsilonKnowledge) * baseKnownProbability
    }

    package static func knownProbability(
        theta: Double,
        difficulty: Double,
        epsilonKnowledge: Double
    ) -> Double {
        adjustedKnownProbability(
            baseKnownProbability: baseKnownProbability(theta: theta, difficulty: difficulty),
            epsilonKnowledge: epsilonKnowledge
        )
    }
}

package struct VocabularyObservationEmission: Codable, Equatable, Sendable {
    package let evidence: VocabularyKnowledgeEvidence
    package let reliability: Double
    package let probabilityGivenKnown: Double
    package let probabilityGivenUnknown: Double
}

package struct VocabularyObservationGoldenFixture: Codable, Equatable, Sendable {
    package let evidence: VocabularyKnowledgeEvidence
    package let theta: Double
    package let difficulty: Double
    package let epsilonKnowledge: Double
    package let latentKnownProbability: Double
    package let evidenceLikelihood: Double
    package let posteriorKnownProbability: Double
}

package struct VocabularyObservationModelManifest: Codable, Equatable, Sendable {
    package let schemaVersion: Int
    package let observationModelVersion: String
    package let knowledgeModelVersion: String
    package let reliabilitySourceVersion: String
    package let defaultEpsilonKnowledge: Double
    package let evidence: [VocabularyObservationEmission]
    package let goldenFixtures: [VocabularyObservationGoldenFixture]
}

/// The single categorical observation model for runtime assessment and offline
/// calibration tooling.
///
/// Evidence reliability (`rho`) describes `P(E | K)` and is never capped by or
/// otherwise coupled to `epsilonKnowledge`. The latter has already acted in the
/// latent-known probability supplied to this model.
package enum VocabularyObservationModel {
    package static let version = "categorical-evidence-v1"
    package static let reliabilitySourceVersion = "cold-start-evidence-v1"

    package static func emission(
        for evidence: VocabularyKnowledgeEvidence
    ) -> VocabularyObservationEmission? {
        guard let reliability = evidence.reliability else { return nil }
        return VocabularyObservationEmission(
            evidence: evidence,
            reliability: reliability,
            probabilityGivenKnown: evidence.supportsKnown ? reliability : 1 - reliability,
            probabilityGivenUnknown: evidence.supportsKnown ? 1 - reliability : reliability
        )
    }

    package static func evidenceLikelihood(
        evidence: VocabularyKnowledgeEvidence,
        latentKnownProbability: Double
    ) -> Double {
        guard let emission = emission(for: evidence) else { return 1 }
        return latentKnownProbability * emission.probabilityGivenKnown
            + (1 - latentKnownProbability) * emission.probabilityGivenUnknown
    }

    package static func posteriorKnownProbability(
        prior: Double,
        evidence: VocabularyKnowledgeEvidence
    ) -> Double {
        guard let emission = emission(for: evidence) else { return prior }
        let knownJoint = prior * emission.probabilityGivenKnown
        let unknownJoint = (1 - prior) * emission.probabilityGivenUnknown
        let total = knownJoint + unknownJoint
        return total > 0 ? knownJoint / total : prior
    }

    package static func manifest() -> VocabularyObservationModelManifest {
        let emissions = VocabularyKnowledgeEvidence.allCases.compactMap(emission(for:))
        let centeredFixtures = emissions.map {
            goldenFixture(
                evidence: $0.evidence,
                theta: 0,
                difficulty: 0,
                epsilonKnowledge: VocabularyKnowledgeModel.defaultEpsilonKnowledge
            )
        }
        let fixtures = centeredFixtures + [
            goldenFixture(
                evidence: .reportedUnknown,
                theta: -2,
                difficulty: 1,
                epsilonKnowledge: 0.05
            ),
            goldenFixture(
                evidence: .verifiedKnown,
                theta: 2,
                difficulty: -1,
                epsilonKnowledge: 0.25
            )
        ]
        return VocabularyObservationModelManifest(
            schemaVersion: 1,
            observationModelVersion: version,
            knowledgeModelVersion: VocabularyKnowledgeModel.version,
            reliabilitySourceVersion: reliabilitySourceVersion,
            defaultEpsilonKnowledge: VocabularyKnowledgeModel.defaultEpsilonKnowledge,
            evidence: emissions,
            goldenFixtures: fixtures
        )
    }

    private static func goldenFixture(
        evidence: VocabularyKnowledgeEvidence,
        theta: Double,
        difficulty: Double,
        epsilonKnowledge: Double
    ) -> VocabularyObservationGoldenFixture {
        let latentKnown = VocabularyKnowledgeModel.knownProbability(
            theta: theta,
            difficulty: difficulty,
            epsilonKnowledge: epsilonKnowledge
        )
        return VocabularyObservationGoldenFixture(
            evidence: evidence,
            theta: theta,
            difficulty: difficulty,
            epsilonKnowledge: epsilonKnowledge,
            latentKnownProbability: latentKnown,
            evidenceLikelihood: evidenceLikelihood(
                evidence: evidence,
                latentKnownProbability: latentKnown
            ),
            posteriorKnownProbability: posteriorKnownProbability(
                prior: latentKnown,
                evidence: evidence
            )
        )
    }
}
