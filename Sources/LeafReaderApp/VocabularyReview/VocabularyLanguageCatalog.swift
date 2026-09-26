import Foundation
import LeafReaderCore

struct VocabularyDefinitionRoutingContext: Sendable {
    let language: VocabularyLanguageID
    let languageRevision: UInt64
    let provider: (any VocabularyDefinitionProviding)?

    var providerDescriptor: VocabularyProviderDescriptor? { provider?.descriptor }
    var identity: VocabularyDefinitionRoutingIdentity {
        VocabularyDefinitionRoutingIdentity(
            language: language,
            languageRevision: languageRevision,
            providerDescriptor: providerDescriptor
        )
    }

    func isSemanticallyEqual(to other: VocabularyDefinitionRoutingContext) -> Bool {
        identity == other.identity
    }
}

struct VocabularyLanguageRuntime: Sendable {
    let language: VocabularyLanguageID
    let profile: VocabularyLanguageProfileDescriptor
    let definitions: (any VocabularyDefinitionProviding)?
    let difficulty: (any DocumentVocabularyDifficultyProviding)?
    let linguisticAnalyzerFactory: VocabularyLinguisticAnalyzerFactory
    let runtimeAvailability: VocabularyLanguageFeatureAvailability
    let linguisticCacheIdentity: VocabularyLinguisticCacheIdentity

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
        runtimeAvailability.status(for: capability)
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

    func definitionProvider(for language: VocabularyLanguageID) -> (any VocabularyDefinitionProviding)? {
        var providersByDescriptor: [VocabularyProviderDescriptor: any VocabularyDefinitionProviding] = [:]
        for runtime in runtimes.values.sorted(by: { $0.language.bcp47 < $1.language.bcp47 }) {
            guard let provider = runtime.definitions else { continue }
            providersByDescriptor[provider.descriptor] = providersByDescriptor[provider.descriptor] ?? provider
        }
        let providers = Array(providersByDescriptor.values)
        switch VocabularyProviderSelection.select(
            language: language,
            descriptors: providers.map(\.descriptor)
        ) {
        case .selected(let descriptor):
            return providersByDescriptor[descriptor]
        case .unavailable, .ambiguous:
            return nil
        }
    }

    var profiles: [VocabularyLanguageProfileDescriptor] {
        runtimes.values.map(\.profile).sorted { $0.language.bcp47 < $1.language.bcp47 }
    }

    func releasedLanguages(for capability: VocabularyLanguageCapability) -> [VocabularyLanguageID] {
        runtimes.values.compactMap { runtime in
            guard runtime.status(for: capability).isAvailable,
                  runtime.releaseState(for: capability) != .disabled else {
                return nil
            }
            return runtime.language
        }.sorted { $0.bcp47 < $1.bcp47 }
    }
}

enum VocabularyLanguageCatalogFactory {
    typealias LinguisticCapabilityProbe = @Sendable (
        VocabularyLanguageID
    ) -> AppleVocabularyLinguisticCapabilities

    static func live(
        definitionProviderOverride: (any VocabularyDefinitionProviding)? = nil,
        linguisticCapabilityProbe: @escaping LinguisticCapabilityProbe = AppleVocabularyLinguisticCapabilities.probe
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
                domainResources: true,
                linguisticCapabilities: linguisticCapabilityProbe(.english)
            ),
            preparationRuntime(
                language: .german,
                version: "de-profile-v1",
                definitions: germanDefinitions,
                difficulty: DocumentVocabularyFrequencyProvider.german,
                formLabels: true,
                domainResources: true,
                linguisticCapabilities: linguisticCapabilityProbe(.german)
            ),
            partialRuntime(
                language: .french,
                version: "fr-profile-v1",
                lemmaEvidence: true,
                linguisticCapabilities: linguisticCapabilityProbe(.french)
            ),
            partialRuntime(
                language: .spanish,
                version: "es-profile-v1",
                lemmaEvidence: true,
                linguisticCapabilities: linguisticCapabilityProbe(.spanish)
            ),
            partialRuntime(
                language: .portuguese,
                version: "pt-profile-v1",
                lemmaEvidence: true,
                linguisticCapabilities: linguisticCapabilityProbe(.portuguese)
            ),
            partialRuntime(
                language: .dutch,
                version: "nl-profile-v1",
                lemmaEvidence: true,
                linguisticCapabilities: linguisticCapabilityProbe(.dutch)
            ),
            partialRuntime(
                language: .russian,
                version: "ru-profile-v1",
                lemmaEvidence: true,
                linguisticCapabilities: linguisticCapabilityProbe(.russian)
            ),
            partialRuntime(
                language: .italian,
                version: "it-profile-v1",
                lemmaEvidence: false,
                linguisticCapabilities: linguisticCapabilityProbe(.italian)
            )
        ])
    }

    private static func preparationRuntime(
        language: VocabularyLanguageID,
        version: String,
        definitions: any VocabularyDefinitionProviding,
        difficulty: any DocumentVocabularyDifficultyProviding,
        formLabels: Bool,
        domainResources: Bool,
        linguisticCapabilities: AppleVocabularyLinguisticCapabilities
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
        let runtimeAvailability = preparationRuntimeAvailability(
            profile: profile,
            capabilities: linguisticCapabilities
        )
        let linguistic = linguisticIdentity(
            language: language,
            profileVersion: version,
            capabilities: linguisticCapabilities
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
            ),
            linguisticAnalyzerFactory: linguisticCapabilities.analyzerFactory,
            runtimeAvailability: runtimeAvailability,
            linguisticCacheIdentity: linguistic
        )
    }

    private static func partialRuntime(
        language: VocabularyLanguageID,
        version: String,
        lemmaEvidence: Bool,
        linguisticCapabilities: AppleVocabularyLinguisticCapabilities
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
        let effectiveCapabilities = lemmaEvidence
            ? linguisticCapabilities
            : AppleVocabularyLinguisticCapabilities(availableTagSchemes: [])
        var runtimeStatuses: [VocabularyLanguageCapability: VocabularyCapabilityAvailability] = [
            .exactForm: .available,
            .morphologicalEvidence: .unavailable(reason: "not registered"),
            .formLabels: .unavailable(reason: "not registered"),
            .definitions: .unavailable(reason: "not registered"),
            .difficulty: .unavailable(reason: "not registered"),
            .domainResources: .unavailable(reason: "not registered"),
            .vocabularyPreparation: .unavailable(reason: "required providers are unavailable")
        ]
        runtimeStatuses[.lemmaEvidence] = lemmaEvidence
            ? schemeAvailability(
                available: effectiveCapabilities.supportsLemma,
                missingReason: "Apple lemma tag scheme unavailable"
            )
            : .unavailable(reason: "disabled by language evidence policy")
        runtimeStatuses[.partOfSpeechEvidence] = lemmaEvidence
            ? schemeAvailability(
                available: effectiveCapabilities.supportsLexicalClass,
                missingReason: "Apple lexical-class tag scheme unavailable"
            )
            : .unavailable(reason: "not registered")
        let runtimeAvailability = VocabularyLanguageFeatureAvailability(runtimeStatuses)
        let linguistic = linguisticIdentity(
            language: language,
            profileVersion: version,
            capabilities: effectiveCapabilities
        )
        return VocabularyLanguageRuntime(
            language: language,
            profile: profile,
            definitions: nil,
            difficulty: nil,
            linguisticAnalyzerFactory: effectiveCapabilities.analyzerFactory,
            runtimeAvailability: runtimeAvailability,
            linguisticCacheIdentity: linguistic
        )
    }

    private static func preparationRuntimeAvailability(
        profile: VocabularyLanguageProfileDescriptor,
        capabilities: AppleVocabularyLinguisticCapabilities
    ) -> VocabularyLanguageFeatureAvailability {
        let lemma = schemeAvailability(
            available: capabilities.supportsLemma,
            missingReason: "Apple lemma tag scheme unavailable"
        )
        let partOfSpeech = schemeAvailability(
            available: capabilities.supportsLexicalClass,
            missingReason: "Apple lexical-class tag scheme unavailable"
        )
        let fullLinguisticEvidence = capabilities.supportsLemma && capabilities.supportsLexicalClass
        let preparation: VocabularyCapabilityAvailability = fullLinguisticEvidence
            ? .available
            : .unavailable(reason: "required linguistic assets unavailable; exact-form vocabulary remains available")
        let formLabels: VocabularyCapabilityAvailability
        if profile.featureAvailability.status(for: .formLabels).isAvailable {
            formLabels = fullLinguisticEvidence
                ? .available
                : .degraded(reason: "linguistic assets unavailable; form labeling may abstain")
        } else {
            formLabels = .unavailable(reason: "not registered")
        }
        return VocabularyLanguageFeatureAvailability([
            .exactForm: .available,
            .lemmaEvidence: lemma,
            .partOfSpeechEvidence: partOfSpeech,
            .morphologicalEvidence: partOfSpeech,
            .formLabels: formLabels,
            .definitions: profile.featureAvailability.status(for: .definitions),
            .difficulty: profile.featureAvailability.status(for: .difficulty),
            .domainResources: profile.featureAvailability.status(for: .domainResources),
            .vocabularyPreparation: preparation
        ])
    }

    private static func schemeAvailability(
        available: Bool,
        missingReason: String
    ) -> VocabularyCapabilityAvailability {
        available ? .available : .unavailable(reason: missingReason)
    }

    private static func linguisticIdentity(
        language: VocabularyLanguageID,
        profileVersion: String,
        capabilities: AppleVocabularyLinguisticCapabilities
    ) -> VocabularyLinguisticCacheIdentity {
        var providers = [VocabularyLinguisticCacheIdentity.exactFormProvider]
        let usesAppleProvider = capabilities.supportsLemma
            || capabilities.supportsLexicalClass
            || capabilities.supportsNameType
        if usesAppleProvider {
            providers.append(VocabularyLinguisticCacheIdentity.builtInProvider)
        }
        if language == .german {
            providers.append(VocabularyLinguisticCacheIdentity.germanDeterministicProvider)
        }
        return VocabularyLinguisticCacheIdentity(
            language: language,
            languageProfileVersion: profileVersion,
            linguisticProviders: providers,
            linguisticRuntimeSignature: usesAppleProvider
                ? capabilities.runtimeSignature
                : VocabularyLinguisticCacheIdentity.currentRuntimeSignature
        )
    }
}
