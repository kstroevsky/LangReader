import Foundation
import NaturalLanguage
import LeafReaderCore

struct AppleVocabularyLanguageRecognizer: VocabularyLanguageRecognizing {
    static let shared = AppleVocabularyLanguageRecognizer()

    let descriptor = VocabularyProviderDescriptor(
        id: "language.apple-natural-language",
        version: "adapter-policy-v1",
        supportedLanguageRanges: []
    )

    func recognize(sample: String) throws -> VocabularyLanguageRecognitionObservation {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 8)
        let candidates = hypotheses.compactMap { language, score -> VocabularyLanguageCandidate? in
            guard let id = VocabularyLanguageID(language.rawValue), score.isFinite else { return nil }
            return VocabularyLanguageCandidate(language: id, rawScore: score)
        }.sorted {
            if ($0.rawScore ?? 0) != ($1.rawScore ?? 0) {
                return ($0.rawScore ?? 0) > ($1.rawScore ?? 0)
            }
            return $0.language.bcp47 < $1.language.bcp47
        }
        let dominant = recognizer.dominantLanguage
            .flatMap { VocabularyLanguageID($0.rawValue) }
            .map { language in
                candidates.first(where: { $0.language == language })
                    ?? VocabularyLanguageCandidate(language: language)
            }
        return VocabularyLanguageRecognitionObservation(
            dominant: dominant,
            candidates: candidates
        )
    }
}

extension VocabularyLanguageID {
    var appleNaturalLanguage: NLLanguage { NLLanguage(rawValue: bcp47) }
}

/// Temporary App-only compatibility for seams that still consume NLLanguage.
/// Unknown resolution becomes `.undetermined`; it never becomes English.
extension VocabularyLanguageDetector {
    static func language(forSample sample: String) -> NLLanguage {
        resolution(forSample: sample, recognizer: AppleVocabularyLanguageRecognizer.shared)
            .languageID?.appleNaturalLanguage ?? .undetermined
    }

    static func language(forContexts contexts: [String]) -> NLLanguage {
        resolution(forContexts: contexts, recognizer: AppleVocabularyLanguageRecognizer.shared)
            .languageID?.appleNaturalLanguage ?? .undetermined
    }

    static func language(pageCount: Int, pageText: (Int) -> String?) -> NLLanguage {
        resolution(
            pageCount: pageCount,
            pageText: pageText,
            recognizer: AppleVocabularyLanguageRecognizer.shared
        ).languageID?.appleNaturalLanguage ?? .undetermined
    }
}
