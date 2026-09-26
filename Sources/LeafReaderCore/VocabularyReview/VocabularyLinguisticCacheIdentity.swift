import Foundation

/// Stable identity for the semantic inputs that make linguistic cache entries
/// reusable. This is deliberately data, not `hashValue`: persisted/session
/// compatibility layers can compare the same canonical fields later.
package struct VocabularySemanticProviderIdentity: Codable, Hashable, Sendable {
    package let id: String
    package let version: String
    package let normalizationVersion: String

    package init(id: String, version: String, normalizationVersion: String) {
        self.id = id
        self.version = version
        self.normalizationVersion = normalizationVersion
    }

    package init(_ descriptor: VocabularyProviderDescriptor) {
        self.init(
            id: descriptor.id,
            version: descriptor.version,
            normalizationVersion: descriptor.normalizationVersion
        )
    }
}

/// Narrow semantic projection used by document lemma indexes and vocabulary
/// library projections. It intentionally includes the host linguistic runtime:
/// Apple's NaturalLanguage models can change with the OS even when LeafReader's
/// adapter code did not.
package struct VocabularyLinguisticCacheIdentity: Codable, Hashable, Sendable {
    package static let schemaVersion = 1
    package static let builtInProvider = VocabularySemanticProviderIdentity(
        id: "linguistics.apple-natural-language",
        version: "document-lemma-index-v1",
        normalizationVersion: VocabularyNormalizationPolicy.currentVersion
    )

    package let fingerprintSchemaVersion: Int
    package let language: VocabularyLanguageID
    package let languageProfileVersion: String?
    package let normalizationVersion: String
    package let lexicalPolicyVersion: String
    package let partOfSpeechPolicyVersion: String
    package let linguisticProviders: [VocabularySemanticProviderIdentity]
    package let linguisticRuntimeSignature: String

    package init(
        language: VocabularyLanguageID,
        languageProfileVersion: String? = nil,
        normalizationVersion: String = VocabularyNormalizationPolicy.currentVersion,
        lexicalPolicyVersion: String = VocabularyLexicalReconciler.policyVersion,
        partOfSpeechPolicyVersion: String = VocabularyPartOfSpeechConfidencePolicy.policyVersion,
        linguisticProviders: [VocabularySemanticProviderIdentity] = [Self.builtInProvider],
        linguisticRuntimeSignature: String = Self.currentRuntimeSignature
    ) {
        fingerprintSchemaVersion = Self.schemaVersion
        self.language = language
        self.languageProfileVersion = languageProfileVersion
        self.normalizationVersion = normalizationVersion
        self.lexicalPolicyVersion = lexicalPolicyVersion
        self.partOfSpeechPolicyVersion = partOfSpeechPolicyVersion
        self.linguisticProviders = linguisticProviders.sorted {
            if $0.id != $1.id { return $0.id < $1.id }
            if $0.version != $1.version { return $0.version < $1.version }
            return $0.normalizationVersion < $1.normalizationVersion
        }
        self.linguisticRuntimeSignature = linguisticRuntimeSignature
    }

    package static var currentRuntimeSignature: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return [
            "apple-natural-language",
            "macos-\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            "schemes-lemma+lexicalClass+nameType"
        ].joined(separator: "|")
    }
}
