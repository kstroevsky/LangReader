import Foundation

/// A stable lexical identity for assessment and newly-created vocabulary cards.
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
/// implementation is registered in version 3.
package protocol VocabularySenseDisambiguating: Sendable {
    func senseKey(language: String, lemma: String, partOfSpeech: VocabularyPartOfSpeech, context: String) -> String?
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
