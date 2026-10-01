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
