import Foundation

/// A stable, resolved lexical identity for assessment and newly-created
/// vocabulary cards. Construction is a domain claim that lemma and coarse POS
/// have already been reconciled; occurrence-level classifiers must not use this
/// type as their direct output.
///
/// `senseKey` is deliberately reserved but remains nil in production until the
/// sense-disambiguation validation gate is met.
package struct VocabularyLexicalItemID: Codable, Hashable, Sendable {
    package let language: String
    package let lemma: String
    package let partOfSpeech: VocabularyPartOfSpeech
    package let senseKey: String?

    package init(
        language: String,
        lemma: String,
        partOfSpeech: VocabularyPartOfSpeech,
        senseKey: String? = nil
    ) {
        self.language = language.lowercased()
        self.lemma = VocabularyTextPolicy.canonicalVocabularyKey(lemma)
        self.partOfSpeech = partOfSpeech
        self.senseKey = senseKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    package var canonicalKey: String {
        [language, lemma, partOfSpeech.rawValue, senseKey ?? ""]
            .map(Self.escape)
            .joined(separator: "|")
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "|", with: "%7C")
    }
}

/// A document-scoped question under reconciliation. An anchor deliberately has
/// no POS and must never be persisted as though it were a resolved lexical item.
package struct VocabularyLexicalAnchorID: Codable, Hashable, Sendable {
    package enum Basis: Codable, Hashable, Sendable {
        case resolvedLemma(String)
        case exactSurface(String)
    }

    package let language: String
    package let basis: Basis

    package init(language: String, basis: Basis) {
        self.language = language.lowercased()
        switch basis {
        case let .resolvedLemma(lemma):
            self.basis = .resolvedLemma(VocabularyTextPolicy.canonicalVocabularyKey(lemma))
        case let .exactSurface(surface):
            self.basis = .exactSurface(
                VocabularyTextPolicy.normalizedVocabularyText(surface)
                    .precomposedStringWithCanonicalMapping
            )
        }
    }

    package var canonicalKey: String {
        let kind: String
        let value: String
        switch basis {
        case let .resolvedLemma(lemma):
            kind = "lemma"
            value = lemma
        case let .exactSurface(surface):
            kind = "surface"
            value = surface
        }
        return ["anchor", language, kind, Self.escape(value)]
            .joined(separator: "|")
    }

    package var resolvedLemma: String? {
        guard case let .resolvedLemma(lemma) = basis else { return nil }
        return lemma
    }

    package var displayValue: String {
        switch basis {
        case let .resolvedLemma(lemma): lemma
        case let .exactSurface(surface): surface
        }
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "|", with: "%7C")
    }
}

package enum VocabularyLinguisticEvidenceSource: String, Codable, CaseIterable, Sendable {
    case appleNaturalLanguage
    case deterministicMorphology
    case lexicalAttestation
    case validationFixture
}

package enum VocabularyEvidenceConfidence: String, Codable, CaseIterable, Comparable, Sendable {
    case unavailable
    case insufficient
    case usable
    case strong

    package var isUsable: Bool {
        self == .usable || self == .strong
    }

    package static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .unavailable: 0
        case .insufficient: 1
        case .usable: 2
        case .strong: 3
        }
    }
}

/// Reserved cross-language feature representation. V1 reconciliation does not
/// depend on feature values, but evidence providers can add them without
/// changing the lexical identity boundary.
package struct VocabularyMorphologicalFeature: Codable, Equatable, Hashable, Sendable {
    package let name: String
    package let value: String

    package init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

package struct VocabularyMorphologicalAnalysis: Codable, Equatable, Sendable {
    package let lemma: String
    package let partOfSpeech: VocabularyPartOfSpeech
    package let features: [VocabularyMorphologicalFeature]
    package let source: VocabularyLinguisticEvidenceSource
    /// A provider score. It is deliberately not named or treated as a
    /// probability because provider calibration has not been established.
    package let rawScore: Double?
    package let confidence: VocabularyEvidenceConfidence

    package init(
        lemma: String,
        partOfSpeech: VocabularyPartOfSpeech,
        features: [VocabularyMorphologicalFeature] = [],
        source: VocabularyLinguisticEvidenceSource,
        rawScore: Double? = nil,
        confidence: VocabularyEvidenceConfidence
    ) {
        self.lemma = VocabularyTextPolicy.canonicalVocabularyKey(lemma)
        self.partOfSpeech = partOfSpeech
        self.features = features
        self.source = source
        self.rawScore = rawScore
        self.confidence = confidence
    }
}

package struct VocabularyOccurrenceAnalysisID: Codable, Equatable, Hashable, Sendable {
    package let unitIndex: Int
    package let utf16Location: Int
    package let utf16Length: Int

    package init(unitIndex: Int, utf16Location: Int, utf16Length: Int) {
        self.unitIndex = unitIndex
        self.utf16Location = utf16Location
        self.utf16Length = utf16Length
    }
}

package struct VocabularyOccurrenceAnalysis: Codable, Equatable, Sendable {
    package let occurrenceID: VocabularyOccurrenceAnalysisID
    package let sourceRange: VocabularyDocumentSourceRange
    package let surface: String
    package let anchor: VocabularyLexicalAnchorID
    package let analyses: [VocabularyMorphologicalAnalysis]
    /// A compact, local-only approximation of independent context. Repeated
    /// identical normalized windows intentionally share this fingerprint.
    package let contextFingerprint: String

    package init(
        occurrenceID: VocabularyOccurrenceAnalysisID,
        sourceRange: VocabularyDocumentSourceRange,
        surface: String,
        anchor: VocabularyLexicalAnchorID,
        analyses: [VocabularyMorphologicalAnalysis],
        contextFingerprint: String
    ) {
        self.occurrenceID = occurrenceID
        self.sourceRange = sourceRange
        self.surface = surface
        self.anchor = anchor
        self.analyses = analyses
        self.contextFingerprint = contextFingerprint
    }
}

package enum VocabularyLexicalResolutionState: String, Codable, CaseIterable, Sendable {
    case resolvedSingle
    case resolvedSplit
    case ambiguous
    case unresolved
}

package enum VocabularyPartOfSpeech: String, Codable, CaseIterable, Sendable {
    case noun
    case verb
    case adjective
    case adverb
    case pronoun
    case determiner
    case preposition
    case conjunction
    case interjection
    case particle
    case other
    case unknown

    package var displayName: String? {
        self == .unknown ? nil : rawValue
    }
}

/// Reserved seam for a future validated same-POS sense splitter. No production
/// implementation is registered in version 4.
package protocol VocabularySenseDisambiguating: Sendable {
    func senseKey(language: String, lemma: String, partOfSpeech: VocabularyPartOfSpeech, context: String) -> String?
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
