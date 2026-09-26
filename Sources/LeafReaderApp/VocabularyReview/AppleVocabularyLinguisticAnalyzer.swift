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

    var formLabelEvidenceProvider: VocabularyFormLabelEvidenceProvider {
        let capabilities = self
        return { request in
            AppleVocabularyFormLabelEvidenceProvider(
                capabilities: capabilities
            ).evidence(for: request)
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

private struct AppleVocabularyFormLabelEvidenceProvider: Sendable {
    private static let clauseBarriers: Set<String> = [
        NLTag.punctuation.rawValue,
        NLTag.sentenceTerminator.rawValue,
        NLTag.conjunction.rawValue
    ]

    let capabilities: AppleVocabularyLinguisticCapabilities

    func evidence(
        for request: VocabularyFormLabelEvidenceRequest
    ) -> VocabularyFormLabelEvidence {
        guard capabilities.supportsLexicalClass else { return .unavailable }
        guard let context = request.context.map(VocabularyTextPolicy.normalizedVocabularyText),
              !context.isEmpty else {
            return VocabularyFormLabelEvidence(
                partOfSpeech: isolatedPartOfSpeech(
                    request.surface,
                    language: request.language
                ),
                hasClauseAuxiliary: false
            )
        }

        var schemes: [NLTagScheme] = [.lexicalClass]
        if capabilities.supportsLemma { schemes.append(.lemma) }
        let tagger = NLTagger(tagSchemes: schemes)
        tagger.string = context
        let fullRange = context.startIndex..<context.endIndex
        tagger.setLanguage(NLLanguage(rawValue: request.language.bcp47), range: fullRange)

        struct Token {
            let surface: String
            let lemma: String
            let partOfSpeech: String
        }
        var tokens: [Token] = []
        tagger.enumerateTags(
            in: fullRange,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace]
        ) { lexicalTag, tokenRange in
            let surface = String(context[tokenRange])
            let lemma = capabilities.supportsLemma
                ? tagger.tag(
                    at: tokenRange.lowerBound,
                    unit: .word,
                    scheme: .lemma
                ).0?.rawValue ?? surface
                : surface
            tokens.append(Token(
                surface: surface,
                lemma: lemma,
                partOfSpeech: lexicalTag?.rawValue ?? ""
            ))
            return true
        }

        let target = VocabularyTextPolicy.canonicalVocabularyKey(request.surface)
        guard let index = tokens.firstIndex(where: {
            VocabularyTextPolicy.canonicalVocabularyKey($0.surface) == target
        }) else {
            return VocabularyFormLabelEvidence(
                partOfSpeech: isolatedPartOfSpeech(
                    request.surface,
                    language: request.language
                ),
                hasClauseAuxiliary: false
            )
        }

        func isAuxiliary(_ token: Token) -> Bool {
            capabilities.supportsLemma
                && token.partOfSpeech == NLTag.verb.rawValue
                && request.auxiliaryLemmas.contains(
                    VocabularyTextPolicy.canonicalVocabularyKey(token.lemma)
                )
        }

        var precedingAuxiliary = false
        for token in tokens[..<index].reversed() {
            if Self.clauseBarriers.contains(token.partOfSpeech) { break }
            if isAuxiliary(token) {
                precedingAuxiliary = true
                break
            }
        }
        let trailingAuxiliary = request.allowsTrailingAuxiliary
            && tokens.indices.contains(index + 1)
            && isAuxiliary(tokens[index + 1])

        return VocabularyFormLabelEvidence(
            partOfSpeech: tokens[index].partOfSpeech.isEmpty ? nil : tokens[index].partOfSpeech,
            hasClauseAuxiliary: precedingAuxiliary || trailingAuxiliary
        )
    }

    private func isolatedPartOfSpeech(
        _ surface: String,
        language: VocabularyLanguageID
    ) -> String? {
        let word = VocabularyTextPolicy.normalizedVocabularyText(surface)
        guard VocabularyTextPolicy.isSingleVocabularyWord(word), !word.isEmpty else { return nil }
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = word
        let range = word.startIndex..<word.endIndex
        tagger.setLanguage(NLLanguage(rawValue: language.bcp47), range: range)
        return tagger.tag(
            at: word.startIndex,
            unit: .word,
            scheme: .lexicalClass
        ).0?.rawValue
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
