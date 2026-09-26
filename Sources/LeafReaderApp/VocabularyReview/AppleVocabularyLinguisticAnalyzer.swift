import Foundation
import NaturalLanguage
import LeafReaderCore

struct AppleVocabularyLinguisticCapabilities: Equatable, Sendable {
    static let adapterPolicyVersion = "apple-natural-language-adapter-v2"

    let availableTagSchemes: Set<String>

    var supportsLemma: Bool { availableTagSchemes.contains(NLTagScheme.lemma.rawValue) }
    var supportsLexicalClass: Bool { availableTagSchemes.contains(NLTagScheme.lexicalClass.rawValue) }
    var supportsNameType: Bool { availableTagSchemes.contains(NLTagScheme.nameType.rawValue) }

    var analyzerFactory: VocabularyLinguisticAnalyzerFactory {
        guard supportsLemma || supportsLexicalClass || supportsNameType else {
            return .exactForm
        }
        let capabilities = self
        return VocabularyLinguisticAnalyzerFactory {
            AppleVocabularyLinguisticAnalyzer(capabilities: capabilities)
        }
    }

    var runtimeSignature: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let schemes = availableTagSchemes.sorted().joined(separator: "+")
        return [
            "apple-natural-language",
            Self.adapterPolicyVersion,
            "macos-\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            "schemes-\(schemes.isEmpty ? "none" : schemes)",
            "model-revision-unknown"
        ].joined(separator: "|")
    }

    static func probe(language: VocabularyLanguageID) -> Self {
        let schemes = NLTagger.availableTagSchemes(
            for: .word,
            language: NLLanguage(rawValue: language.bcp47)
        )
        return Self(availableTagSchemes: Set(schemes.map(\.rawValue)))
    }
}

/// App-owned adapter for Apple's NaturalLanguage framework. Instances are
/// worker-local: `NLTagger` is mutable and must never be shared across the
/// bounded concurrent workers in `VocabularyDocumentLemmaIndex`.
final class AppleVocabularyLinguisticAnalyzer: @unchecked Sendable, VocabularyLinguisticAnalyzing {
    private let capabilities: AppleVocabularyLinguisticCapabilities
    private let tokenTagger: NLTagger?
    private let isolatedLemmaTagger: NLTagger?
    private let exactFormAnalyzer = VocabularyLinguisticAnalyzerFactory.exactForm.makeAnalyzer()

    init(capabilities: AppleVocabularyLinguisticCapabilities) {
        self.capabilities = capabilities
        var schemes: [NLTagScheme] = []
        if capabilities.supportsLemma { schemes.append(.lemma) }
        if capabilities.supportsLexicalClass { schemes.append(.lexicalClass) }
        if capabilities.supportsNameType { schemes.append(.nameType) }
        tokenTagger = schemes.isEmpty ? nil : NLTagger(tagSchemes: schemes)
        isolatedLemmaTagger = capabilities.supportsLemma
            ? NLTagger(tagSchemes: [.lemma])
            : nil
    }

    func tokenEvidence(
        in text: String,
        language: VocabularyLanguageID
    ) -> [VocabularyLinguisticTokenEvidence] {
        guard !text.isEmpty else { return [] }
        guard let tokenTagger else {
            return exactFormAnalyzer.tokenEvidence(in: text, language: language)
        }
        let appleLanguage = NLLanguage(rawValue: language.bcp47)
        tokenTagger.string = text
        let fullRange = text.startIndex..<text.endIndex
        tokenTagger.setLanguage(appleLanguage, range: fullRange)
        let enumerationScheme: NLTagScheme
        if capabilities.supportsLemma {
            enumerationScheme = .lemma
        } else if capabilities.supportsLexicalClass {
            enumerationScheme = .lexicalClass
        } else {
            enumerationScheme = .nameType
        }

        var evidence: [VocabularyLinguisticTokenEvidence] = []
        tokenTagger.enumerateTags(
            in: fullRange,
            unit: .word,
            scheme: enumerationScheme,
            options: [.omitWhitespace, .omitPunctuation]
        ) { _, tokenRange in
            let taggedLemma = capabilities.supportsLemma
                ? tokenTagger.tag(
                    at: tokenRange.lowerBound,
                    unit: .word,
                    scheme: .lemma
                ).0?.rawValue
                : nil
            let hypotheses: [String: Double]
            if capabilities.supportsLexicalClass {
                hypotheses = tokenTagger.tagHypotheses(
                    at: tokenRange.lowerBound,
                    unit: .word,
                    scheme: .lexicalClass,
                    maximumCount: 2
                ).0
            } else {
                hypotheses = [:]
            }
            let nameTag = capabilities.supportsNameType
                ? tokenTagger.tag(
                    at: tokenRange.lowerBound,
                    unit: .word,
                    scheme: .nameType
                ).0
                : nil
            evidence.append(VocabularyLinguisticTokenEvidence(
                range: NSRange(tokenRange, in: text),
                taggedLemma: taggedLemma,
                lexicalClassHypotheses: hypotheses,
                isConfidentName: nameTag == .personalName
                    || nameTag == .placeName
                    || nameTag == .organizationName
            ))
            return true
        }
        return evidence
    }

    func isolatedLemma(
        for surfaceForm: String,
        language: VocabularyLanguageID
    ) -> String? {
        guard let isolatedLemmaTagger else { return nil }
        let word = VocabularyTextPolicy.normalizedVocabularyText(surfaceForm)
        guard VocabularyTextPolicy.isSingleVocabularyWord(word), !word.isEmpty else { return nil }
        isolatedLemmaTagger.string = word
        let range = word.startIndex..<word.endIndex
        isolatedLemmaTagger.setLanguage(NLLanguage(rawValue: language.bcp47), range: range)
        return isolatedLemmaTagger.tag(
            at: word.startIndex,
            unit: .word,
            scheme: .lemma
        ).0?.rawValue
    }
}
