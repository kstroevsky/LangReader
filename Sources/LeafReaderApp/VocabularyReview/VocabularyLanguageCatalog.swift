import Foundation
import LeafReaderCore

struct VocabularyLanguageRuntime: Sendable {
    let language: VocabularyLanguageID
    let profile: VocabularyLanguageProfileDescriptor
    let definitions: (any VocabularyDefinitionProviding)?
    let difficulty: (any DocumentVocabularyDifficultyProviding)?

    var linguisticCacheIdentity: VocabularyLinguisticCacheIdentity {
        VocabularyLinguisticCacheIdentity(
            language: language,
            languageProfileVersion: profile.version
        )
    }

    func preparationCompatibilityFingerprint(
        algorithmVersion: Int
    ) -> VocabularyPreparationCompatibilityFingerprint? {
        guard let definitions, let difficulty else { return nil }
        let linguistic = linguisticCacheIdentity
        return VocabularyPreparationCompatibilityFingerprint(
            algorithmVersion: algorithmVersion,
            language: language,
            languageProfileVersion: profile.version,
            lexicalPolicyVersion: linguistic.lexicalPolicyVersion,
            linguisticProviders: linguistic.linguisticProviders,
            linguisticRuntimeSignature: linguistic.linguisticRuntimeSignature,
            difficultyProvider: difficulty.semanticIdentity,
            definitionProvider: VocabularySemanticProviderIdentity(definitions.descriptor),
            normalizationVersion: linguistic.normalizationVersion
        )
    }

    func status(for capability: VocabularyLanguageCapability) -> VocabularyCapabilityAvailability {
        profile.featureAvailability.status(for: capability)
    }

    func releaseState(for capability: VocabularyLanguageCapability) -> VocabularyFeatureReleaseState {
        profile.releaseState(for: capability)
    }
}

struct VocabularyLanguageCatalog: Sendable {
    private let runtimes: [VocabularyLanguageID: VocabularyLanguageRuntime]

    init(runtimes: [VocabularyLanguageRuntime]) {
        self.runtimes = Dictionary(uniqueKeysWithValues: runtimes.map { ($0.language, $0) })
    }

    func resolve(language: VocabularyLanguageID) -> VocabularyLanguageRuntime? {
        runtimes[language]
    }

    var profiles: [VocabularyLanguageProfileDescriptor] {
        runtimes.values.map(\.profile).sorted { $0.language.bcp47 < $1.language.bcp47 }
    }

    func releasedLanguages(for capability: VocabularyLanguageCapability) -> [VocabularyLanguageID] {
        profiles.compactMap { profile in
            guard profile.featureAvailability.status(for: capability).isAvailable,
                  profile.releaseState(for: capability) != .disabled else {
                return nil
            }
            return profile.language
        }
    }
}

enum VocabularyLanguageCatalogFactory {
    static func live(
        definitionProviderOverride: (any VocabularyDefinitionProviding)? = nil
    ) -> VocabularyLanguageCatalog {
        let englishDefinitions: any VocabularyDefinitionProviding = definitionProviderOverride
            ?? EnglishECDICTVocabularyDefinitionProvider()
        let germanDefinitions: any VocabularyDefinitionProviding = definitionProviderOverride
            ?? GermanWiktionaryVocabularyDefinitionProvider()

        return VocabularyLanguageCatalog(runtimes: [
            preparationRuntime(
                language: .english,
                version: "en-profile-v1",
                definitions: englishDefinitions,
                difficulty: DocumentVocabularyFrequencyProvider.english,
                formLabels: true,
                domainResources: true
            ),
            preparationRuntime(
                language: .german,
                version: "de-profile-v1",
                definitions: germanDefinitions,
                difficulty: DocumentVocabularyFrequencyProvider.german,
                formLabels: true,
                domainResources: true
            ),
            partialRuntime(language: .french, version: "fr-profile-v1", lemmaEvidence: true),
            partialRuntime(language: .spanish, version: "es-profile-v1", lemmaEvidence: true),
            partialRuntime(language: .portuguese, version: "pt-profile-v1", lemmaEvidence: true),
            partialRuntime(language: .dutch, version: "nl-profile-v1", lemmaEvidence: true),
            partialRuntime(language: .russian, version: "ru-profile-v1", lemmaEvidence: true),
            partialRuntime(language: .italian, version: "it-profile-v1", lemmaEvidence: false)
        ])
    }

    private static func preparationRuntime(
        language: VocabularyLanguageID,
        version: String,
        definitions: any VocabularyDefinitionProviding,
        difficulty: any DocumentVocabularyDifficultyProviding,
        formLabels: Bool,
        domainResources: Bool
    ) -> VocabularyLanguageRuntime {
        let availability = VocabularyLanguageFeatureAvailability([
            .exactForm: .available,
            .lemmaEvidence: .available,
            .partOfSpeechEvidence: .available,
            .morphologicalEvidence: .available,
            .formLabels: formLabels ? .available : .unavailable(reason: "not registered"),
            .definitions: .available,
            .difficulty: .available,
            .domainResources: domainResources ? .available : .unavailable(reason: "not registered"),
            .vocabularyPreparation: .available
        ])
        let profile = VocabularyLanguageProfileDescriptor(
            language: language,
            version: version,
            featureAvailability: availability,
            releaseStates: [
                .exactForm: .production,
                .lemmaEvidence: .production,
                .partOfSpeechEvidence: .production,
                .morphologicalEvidence: .production,
                .formLabels: formLabels ? .production : .disabled,
                .definitions: .production,
                .difficulty: .production,
                .domainResources: domainResources ? .production : .disabled,
                .vocabularyPreparation: .production
            ]
        )
        let linguistic = VocabularyLinguisticCacheIdentity(
            language: language,
            languageProfileVersion: version
        )
        let calibrationTarget = VocabularyCalibrationCompatibilityTarget(
            language: language,
            languageProfileVersion: version,
            lexicalPolicyVersion: linguistic.lexicalPolicyVersion,
            linguisticProviders: linguistic.linguisticProviders,
            linguisticRuntimeSignature: linguistic.linguisticRuntimeSignature,
            difficultyProvider: difficulty.semanticIdentity,
            normalizationVersion: linguistic.normalizationVersion
        )
        return VocabularyLanguageRuntime(
            language: language,
            profile: profile,
            definitions: definitions,
            difficulty: DocumentVocabularyFrequencyProvider.calibrated(
                base: difficulty,
                target: calibrationTarget
            )
        )
    }

    private static func partialRuntime(
        language: VocabularyLanguageID,
        version: String,
        lemmaEvidence: Bool
    ) -> VocabularyLanguageRuntime {
        let availability = VocabularyLanguageFeatureAvailability([
            .exactForm: .available,
            .lemmaEvidence: lemmaEvidence
                ? .available
                : .unavailable(reason: "disabled by language evidence policy"),
            .partOfSpeechEvidence: lemmaEvidence
                ? .available
                : .unavailable(reason: "not registered"),
            .morphologicalEvidence: .unavailable(reason: "not registered"),
            .formLabels: .unavailable(reason: "not registered"),
            .definitions: .unavailable(reason: "not registered"),
            .difficulty: .unavailable(reason: "not registered"),
            .domainResources: .unavailable(reason: "not registered"),
            .vocabularyPreparation: .unavailable(reason: "required providers are unavailable")
        ])
        let profile = VocabularyLanguageProfileDescriptor(
            language: language,
            version: version,
            featureAvailability: availability,
            releaseStates: [
                .exactForm: .production,
                .lemmaEvidence: lemmaEvidence ? .experimental : .disabled,
                .partOfSpeechEvidence: lemmaEvidence ? .experimental : .disabled,
                .vocabularyPreparation: .disabled
            ]
        )
        return VocabularyLanguageRuntime(
            language: language,
            profile: profile,
            definitions: nil,
            difficulty: nil
        )
    }
}
