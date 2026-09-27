import Foundation

/// Stable, provider-independent language identity for vocabulary semantics.
///
/// The v1 parser accepts the BCP-47 subset LeafReader can safely route today:
/// language/extlang/script/region/variant subtags. Extensions, private-use-only
/// tags, and semantic special tags (`und`, `mul`, `zxx`) are intentionally not
/// resolved identities. They may still be retained by import adapters as raw
/// metadata without entering provider routing.
package struct VocabularyLanguageID: Codable, Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    package static let canonicalizationVersion = 1

    package let bcp47: String

    package init?(_ rawValue: String) {
        guard let canonical = Self.canonicalize(rawValue) else { return nil }
        bcp47 = canonical
    }

    package init(stringLiteral value: String) {
        guard let canonical = Self.canonicalize(value) else {
            preconditionFailure("Invalid resolved BCP-47 language literal: \(value)")
        }
        bcp47 = canonical
    }

    package static let english: VocabularyLanguageID = "en"
    package static let german: VocabularyLanguageID = "de"
    package static let french: VocabularyLanguageID = "fr"
    package static let spanish: VocabularyLanguageID = "es"
    package static let portuguese: VocabularyLanguageID = "pt"
    package static let dutch: VocabularyLanguageID = "nl"
    package static let russian: VocabularyLanguageID = "ru"
    package static let italian: VocabularyLanguageID = "it"

    package var rawValue: String { bcp47 }
    package var description: String { bcp47 }
    package var primaryLanguage: String { bcp47.split(separator: "-").first.map(String.init) ?? bcp47 }
    package var subtags: [String] { bcp47.split(separator: "-").map(String.init) }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(bcp47)
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = VocabularyLanguageID(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid or unsupported resolved BCP-47 language tag: \(raw)"
            )
        }
        self = value
    }

    private static func canonicalize(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("_"),
              !trimmed.contains("@"),
              trimmed.unicodeScalars.allSatisfy({ scalar in
                  scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-")
              }) else { return nil }

        let rawParts = trimmed.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard !rawParts.isEmpty, rawParts.allSatisfy({ !$0.isEmpty }) else { return nil }

        let primary = rawParts[0]
        guard (2...8).contains(primary.count), primary.allSatisfy(\.isASCIIAlpha) else { return nil }
        let primaryLower = primary.lowercased()
        guard !["und", "mul", "zxx"].contains(primaryLower) else { return nil }

        var canonical: [String] = [primaryLower]
        var index = 1

        // RFC 5646 extlang: up to three 3-letter subtags following a 2-3
        // letter primary language. Preserve them rather than collapsing them.
        if (2...3).contains(primary.count) {
            var extlangCount = 0
            while index < rawParts.count,
                  extlangCount < 3,
                  rawParts[index].count == 3,
                  rawParts[index].allSatisfy(\.isASCIIAlpha) {
                canonical.append(rawParts[index].lowercased())
                extlangCount += 1
                index += 1
            }
        }

        if index < rawParts.count,
           rawParts[index].count == 4,
           rawParts[index].allSatisfy(\.isASCIIAlpha) {
            let lower = rawParts[index].lowercased()
            canonical.append(lower.prefix(1).uppercased() + lower.dropFirst())
            index += 1
        }

        if index < rawParts.count {
            let region = rawParts[index]
            if region.count == 2, region.allSatisfy(\.isASCIIAlpha) {
                canonical.append(region.uppercased())
                index += 1
            } else if region.count == 3, region.allSatisfy(\.isASCIIDigit) {
                canonical.append(region)
                index += 1
            }
        }

        while index < rawParts.count {
            let part = rawParts[index]
            // Singletons introduce extensions (`u`, `t`, etc.) or private use
            // (`x`). ADR-0002 keeps these outside v1 provider routing.
            guard part.count != 1 else { return nil }
            let isVariant = ((5...8).contains(part.count) && part.allSatisfy(\.isASCIIAlphanumeric))
                || (part.count == 4 && part.first?.isASCIIDigit == true && part.allSatisfy(\.isASCIIAlphanumeric))
            guard isVariant else { return nil }
            canonical.append(part.lowercased())
            index += 1
        }

        return canonical.joined(separator: "-")
    }
}

package struct VocabularyLanguageRange: Codable, Hashable, Sendable {
    package let language: VocabularyLanguageID
    package let includesDescendants: Bool

    package init(language: VocabularyLanguageID, includesDescendants: Bool = false) {
        self.language = language
        self.includesDescendants = includesDescendants
    }

    package init?(_ rawValue: String) {
        let descendants = rawValue.hasSuffix("-*")
        let tag = descendants ? String(rawValue.dropLast(2)) : rawValue
        guard let language = VocabularyLanguageID(tag) else { return nil }
        self.init(language: language, includesDescendants: descendants)
    }

    package func matchSpecificity(for requested: VocabularyLanguageID) -> Int? {
        if requested == language { return 10_000 + language.subtags.count }
        guard includesDescendants else { return nil }
        let base = language.subtags
        let candidate = requested.subtags
        guard candidate.count > base.count,
              Array(candidate.prefix(base.count)).map({ $0.lowercased() })
                == base.map({ $0.lowercased() }) else {
            return nil
        }
        return base.count
    }
}

package struct VocabularyProviderDescriptor: Codable, Hashable, Sendable {
    package let id: String
    package let version: String
    package let supportedLanguageRanges: [VocabularyLanguageRange]
    package let normalizationVersion: String

    package init(
        id: String,
        version: String,
        supportedLanguageRanges: [VocabularyLanguageRange],
        normalizationVersion: String = VocabularyNormalizationPolicy.currentVersion
    ) {
        self.id = id
        self.version = version
        self.supportedLanguageRanges = supportedLanguageRanges
        self.normalizationVersion = normalizationVersion
    }

    package func matchSpecificity(for language: VocabularyLanguageID) -> Int? {
        supportedLanguageRanges.compactMap { $0.matchSpecificity(for: language) }.max()
    }

    package func supports(_ language: VocabularyLanguageID) -> Bool {
        matchSpecificity(for: language) != nil
    }
}

package enum VocabularyProviderSelection {
    package enum Result: Equatable, Sendable {
        case selected(VocabularyProviderDescriptor)
        case unavailable
        case ambiguous([VocabularyProviderDescriptor])
    }

    /// Deterministic capability-local matching. Exact declarations win over
    /// broader compatible ranges. Equal-specificity matches require an explicit
    /// composition priority; without one the capability is unavailable rather
    /// than depending on registration order.
    package static func select(
        language: VocabularyLanguageID,
        descriptors: [VocabularyProviderDescriptor],
        priorityByProviderID: [String: Int] = [:]
    ) -> Result {
        let matches = descriptors.compactMap { descriptor -> (VocabularyProviderDescriptor, Int, Int)? in
            guard let specificity = descriptor.matchSpecificity(for: language) else { return nil }
            return (descriptor, specificity, priorityByProviderID[descriptor.id] ?? 0)
        }
        guard let bestSpecificity = matches.map({ $0.1 }).max() else { return .unavailable }
        let specificityMatches = matches.filter { $0.1 == bestSpecificity }
        let bestPriority = specificityMatches.map({ $0.2 }).max() ?? 0
        let finalists = specificityMatches.filter { $0.2 == bestPriority }.map { $0.0 }
        guard finalists.count == 1, let selected = finalists.first else {
            return .ambiguous(finalists.sorted { $0.id < $1.id })
        }
        return .selected(selected)
    }
}

package enum VocabularyLanguageProvenance: String, Codable, Hashable, Sendable {
    case userSelected
    case automaticDetection
    case persistedDocumentMetadata
    case segmentDetection
}

package enum VocabularyLanguageUndeterminedReason: String, Codable, Hashable, Sendable {
    case notYetAnalyzed
    case insufficientText
    case inconclusiveRecognition
    case providerFailure
}

package struct VocabularyLanguageCandidate: Codable, Hashable, Sendable {
    package let language: VocabularyLanguageID
    package let rawScore: Double?

    package init(language: VocabularyLanguageID, rawScore: Double? = nil) {
        self.language = language
        self.rawScore = rawScore
    }
}

package struct VocabularyLanguageEvidence: Codable, Hashable, Sendable {
    package let provider: VocabularyProviderDescriptor
    package let candidates: [VocabularyLanguageCandidate]
    package let sampledCharacterCount: Int
    package let sampledUnitCount: Int
    package let undeterminedReason: VocabularyLanguageUndeterminedReason?

    package init(
        provider: VocabularyProviderDescriptor,
        candidates: [VocabularyLanguageCandidate] = [],
        sampledCharacterCount: Int = 0,
        sampledUnitCount: Int = 0,
        undeterminedReason: VocabularyLanguageUndeterminedReason? = nil
    ) {
        self.provider = provider
        self.candidates = candidates
        self.sampledCharacterCount = sampledCharacterCount
        self.sampledUnitCount = sampledUnitCount
        self.undeterminedReason = undeterminedReason
    }

    package static func unresolved(
        _ reason: VocabularyLanguageUndeterminedReason,
        sampledCharacterCount: Int = 0,
        sampledUnitCount: Int = 0
    ) -> VocabularyLanguageEvidence {
        VocabularyLanguageEvidence(
            provider: VocabularyProviderDescriptor(
                id: "language.none",
                version: "1",
                supportedLanguageRanges: []
            ),
            sampledCharacterCount: sampledCharacterCount,
            sampledUnitCount: sampledUnitCount,
            undeterminedReason: reason
        )
    }
}

package struct VocabularyResolvedLanguage: Codable, Hashable, Sendable {
    package let id: VocabularyLanguageID
    package let provenance: VocabularyLanguageProvenance
    package let evidence: VocabularyLanguageEvidence?

    package init(
        id: VocabularyLanguageID,
        provenance: VocabularyLanguageProvenance,
        evidence: VocabularyLanguageEvidence? = nil
    ) {
        self.id = id
        self.provenance = provenance
        self.evidence = evidence
    }
}

package enum VocabularyLanguageResolution: Codable, Hashable, Sendable {
    case resolved(VocabularyResolvedLanguage)
    case undetermined(VocabularyLanguageEvidence)

    package static let notYetAnalyzed: VocabularyLanguageResolution = .undetermined(
        .unresolved(.notYetAnalyzed)
    )

    package var resolvedLanguage: VocabularyResolvedLanguage? {
        guard case let .resolved(value) = self else { return nil }
        return value
    }

    package var languageID: VocabularyLanguageID? { resolvedLanguage?.id }
}

package enum VocabularyLanguageSelection: Codable, Hashable, Sendable {
    case auto
    case manual(VocabularyLanguageID)
}

package enum VocabularyLanguageCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case exactForm
    case lemmaEvidence
    case partOfSpeechEvidence
    case morphologicalEvidence
    case formLabels
    case definitions
    case difficulty
    case domainResources
    case vocabularyPreparation
}

package enum VocabularyCapabilityAvailability: Codable, Hashable, Sendable {
    case available
    case degraded(reason: String)
    case unavailable(reason: String)

    package var isAvailable: Bool {
        switch self {
        case .available, .degraded: true
        case .unavailable: false
        }
    }
}

package enum VocabularyFeatureReleaseState: String, Codable, Hashable, Sendable {
    case production
    case experimental
    case disabled
}

package struct VocabularyLanguageFeatureAvailability: Codable, Hashable, Sendable {
    private let capabilities: [VocabularyLanguageCapability: VocabularyCapabilityAvailability]

    package init(_ capabilities: [VocabularyLanguageCapability: VocabularyCapabilityAvailability]) {
        self.capabilities = capabilities
    }

    package func status(for capability: VocabularyLanguageCapability) -> VocabularyCapabilityAvailability {
        capabilities[capability] ?? .unavailable(reason: "not registered")
    }
}

package struct VocabularyLanguageProfileDescriptor: Codable, Hashable, Sendable {
    package let language: VocabularyLanguageID
    package let version: String
    package let featureAvailability: VocabularyLanguageFeatureAvailability
    package let releaseStates: [VocabularyLanguageCapability: VocabularyFeatureReleaseState]

    package init(
        language: VocabularyLanguageID,
        version: String,
        featureAvailability: VocabularyLanguageFeatureAvailability,
        releaseStates: [VocabularyLanguageCapability: VocabularyFeatureReleaseState]
    ) {
        self.language = language
        self.version = version
        self.featureAvailability = featureAvailability
        self.releaseStates = releaseStates
    }

    package func releaseState(for capability: VocabularyLanguageCapability) -> VocabularyFeatureReleaseState {
        releaseStates[capability] ?? .disabled
    }
}

package struct VocabularyLanguageFeatureMatrixRow: Equatable, Sendable {
    package let language: VocabularyLanguageID
    package let exact: VocabularyFeatureReleaseState
    package let lemma: VocabularyFeatureReleaseState
    package let partOfSpeech: VocabularyFeatureReleaseState
    package let forms: VocabularyFeatureReleaseState
    package let definition: VocabularyFeatureReleaseState
    package let difficulty: VocabularyFeatureReleaseState
    package let preparation: VocabularyFeatureReleaseState
}

/// Deterministic product capability report derived from profile declarations.
/// Runtime asset availability is intentionally excluded: this matrix answers
/// what the product registers/releases, while runtime status answers what this
/// particular machine can execute right now.
package enum VocabularyLanguageFeatureMatrix {
    package static func rows(
        profiles: [VocabularyLanguageProfileDescriptor]
    ) -> [VocabularyLanguageFeatureMatrixRow] {
        profiles
            .sorted { $0.language.bcp47 < $1.language.bcp47 }
            .map { profile in
                VocabularyLanguageFeatureMatrixRow(
                    language: profile.language,
                    exact: declaredState(profile, .exactForm),
                    lemma: declaredState(profile, .lemmaEvidence),
                    partOfSpeech: declaredState(profile, .partOfSpeechEvidence),
                    forms: declaredState(profile, .formLabels),
                    definition: declaredState(profile, .definitions),
                    difficulty: declaredState(profile, .difficulty),
                    preparation: declaredState(profile, .vocabularyPreparation)
                )
            }
    }

    package static func markdown(
        profiles: [VocabularyLanguageProfileDescriptor]
    ) -> String {
        let header = "Language | Exact | Lemma | POS | Forms | Definition | Difficulty | Preparation"
        let separator = "--- | --- | --- | --- | --- | --- | --- | ---"
        let body = rows(profiles: profiles).map { row in
            [
                row.language.bcp47,
                row.exact.rawValue,
                row.lemma.rawValue,
                row.partOfSpeech.rawValue,
                row.forms.rawValue,
                row.definition.rawValue,
                row.difficulty.rawValue,
                row.preparation.rawValue
            ].joined(separator: " | ")
        }
        return ([header, separator] + body).joined(separator: "\n")
    }

    private static func declaredState(
        _ profile: VocabularyLanguageProfileDescriptor,
        _ capability: VocabularyLanguageCapability
    ) -> VocabularyFeatureReleaseState {
        guard profile.featureAvailability.status(for: capability).isAvailable else {
            return .disabled
        }
        return profile.releaseState(for: capability)
    }
}

package enum VocabularyNormalizationPolicy {
    /// Preserves the existing EN/DE persisted-key behavior during ADR-0002's
    /// initial migration. Future multilingual normalization must allocate a new
    /// semantic version and migration contract rather than silently changing
    /// existing keys.
    package static let currentVersion = "legacy-de-lowercase-v1"
}

private extension Character {
    var isASCIIAlpha: Bool {
        guard let scalar = unicodeScalars.only, scalar.isASCII else { return false }
        return (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }

    var isASCIIDigit: Bool {
        guard let scalar = unicodeScalars.only, scalar.isASCII else { return false }
        return (48...57).contains(scalar.value)
    }

    var isASCIIAlphanumeric: Bool { isASCIIAlpha || isASCIIDigit }
}

private extension String.UnicodeScalarView {
    var only: Unicode.Scalar? {
        guard count == 1 else { return nil }
        return first
    }
}
