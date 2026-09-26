import CryptoKit
import Foundation

package struct VocabularyDifficultyProviderSemanticIdentity: Codable, Equatable, Hashable, Sendable {
    package let providerID: String
    package let providerVersion: String
    package let calibrationPackIDAndVersion: String?

    package init(
        providerID: String,
        providerVersion: String,
        calibrationPackIDAndVersion: String? = nil
    ) {
        self.providerID = providerID
        self.providerVersion = providerVersion
        self.calibrationPackIDAndVersion = calibrationPackIDAndVersion
    }
}

package enum VocabularyAssessmentCompatibilityPolicy {
    package static let version = [
        "assessment-policy-v1",
        VocabularyKnowledgeModel.version,
        VocabularyObservationModel.version,
        VocabularyObservationModel.reliabilitySourceVersion
    ].joined(separator: "|")
}

/// Complete semantic identity for restoring assessment-derived state. The
/// representation is intentionally Codable with canonical key ordering; never
/// replace this with Swift's process-randomized `hashValue`.
package struct VocabularyPreparationCompatibilityFingerprint: Codable, Equatable, Hashable, Sendable {
    package static let schemaVersion = 1

    package let fingerprintSchemaVersion: Int
    package let algorithmVersion: Int
    package let language: VocabularyLanguageID
    package let languageProfileVersion: String
    package let lexicalPolicyVersion: String
    package let linguisticProviders: [VocabularySemanticProviderIdentity]
    package let linguisticRuntimeSignature: String
    package let difficultyProviderID: String
    package let difficultyProviderVersion: String
    package let calibrationPackIDAndVersion: String?
    package let definitionProvider: VocabularySemanticProviderIdentity
    package let normalizationVersion: String
    package let assessmentPolicyVersion: String
    package let degradedModes: [String]

    package init(
        algorithmVersion: Int,
        language: VocabularyLanguageID,
        languageProfileVersion: String,
        lexicalPolicyVersion: String = VocabularyLexicalReconciler.policyVersion,
        linguisticProviders: [VocabularySemanticProviderIdentity],
        linguisticRuntimeSignature: String,
        difficultyProvider: VocabularyDifficultyProviderSemanticIdentity,
        definitionProvider: VocabularySemanticProviderIdentity,
        normalizationVersion: String = VocabularyNormalizationPolicy.currentVersion,
        assessmentPolicyVersion: String = VocabularyAssessmentCompatibilityPolicy.version,
        degradedModes: [String] = []
    ) {
        fingerprintSchemaVersion = Self.schemaVersion
        self.algorithmVersion = algorithmVersion
        self.language = language
        self.languageProfileVersion = languageProfileVersion
        self.lexicalPolicyVersion = lexicalPolicyVersion
        self.linguisticProviders = linguisticProviders.sorted {
            if $0.id != $1.id { return $0.id < $1.id }
            if $0.version != $1.version { return $0.version < $1.version }
            return $0.normalizationVersion < $1.normalizationVersion
        }
        self.linguisticRuntimeSignature = linguisticRuntimeSignature
        difficultyProviderID = difficultyProvider.providerID
        difficultyProviderVersion = difficultyProvider.providerVersion
        calibrationPackIDAndVersion = difficultyProvider.calibrationPackIDAndVersion
        self.definitionProvider = definitionProvider
        self.normalizationVersion = normalizationVersion
        self.assessmentPolicyVersion = assessmentPolicyVersion
        self.degradedModes = degradedModes.sorted()
    }

    package var stableDigest: String {
        Self.sha256(Self.canonicalData(self))
    }

    private static func canonicalData<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Every stored field is a total Codable value. Returning an empty data
        // sentinel here would silently make incompatible semantics collide.
        guard let data = try? encoder.encode(value) else {
            preconditionFailure("Vocabulary compatibility fingerprint must be encodable")
        }
        return data
    }

    fileprivate static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

package enum VocabularyPreparationStateIdentity {
    package static func text(documentID: String, texts: [String]) -> String {
        struct Payload: Codable {
            let documentID: String
            let texts: [String]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(Payload(documentID: documentID, texts: texts)) else {
            preconditionFailure("Vocabulary text identity must be encodable")
        }
        return VocabularyPreparationCompatibilityFingerprint.sha256(data)
    }

    package static func inventory(_ inventory: DocumentVocabularyInventory) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(inventory) else {
            preconditionFailure("Vocabulary inventory identity must be encodable")
        }
        return VocabularyPreparationCompatibilityFingerprint.sha256(data)
    }
}
