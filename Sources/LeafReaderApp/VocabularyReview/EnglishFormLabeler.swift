import Foundation
import NaturalLanguage

/// Derives a grammatical form label for an English surface form, offline.
///
/// Mirrors `GermanFormLabeler`, including its guiding rule: **never guess**.
/// Every rule here rests on a signal measured to be reliable; anything the
/// tagger cannot prove is reported under the honest coarse label
/// `.finiteVerb` ("Conjugated form") or left unlabeled, never guessed.
///
/// Two measurements shaped the rules:
///   * Attributive participles ("the **completed** work") are still tagged
///     `Verb`, so a bare "-ed means past tense" rule produces false positives.
///     Past tense is therefore never claimed — such forms fall to `.finiteVerb`.
///   * Comparatives ("bigger") are tagged `Adverb`, exactly as in German, so no
///     adjective-specific label is trustworthy here either.
enum EnglishFormLabeler {
    /// Bumped whenever the heuristics in this file change, so labels persisted
    /// by an older ruleset are treated as absent. Shares the cache table with
    /// the German labeler, which is why the two versions move independently.
    static let labelingVersion = 1

    /// Auxiliaries that prove a following/preceding participle.
    private static let auxiliaryLemmas: Set<String> = ["have", "be"]
    /// Token classes that end the clause an auxiliary can govern.
    private static let clauseBarriers: Set<String> = [
        "Conjunction", "Punctuation", "SentenceTerminator"
    ]

    /// Labels `surfaceForm` given its lemma, optionally using the sentence it
    /// appeared in.
    ///
    /// Context is what separates a past participle from any other past form:
    /// "has walked" is a participle, "walked" alone is not provably one.
    static func label(
        surfaceForm rawSurface: String,
        lemma rawLemma: String,
        context: String? = nil
    ) -> WordFormLabel? {
        let surface = VocabularyTextPolicy.normalizedVocabularyText(rawSurface)
        let lemma = VocabularyTextPolicy.normalizedVocabularyText(rawLemma)
        guard VocabularyTextPolicy.isSingleEnglishWord(surface), !lemma.isEmpty else {
            return nil
        }
        // Mirrors the German gate: the labeler decides for itself, so a document
        // in another language never shows English grammatical labels.
        guard isEnglish(context ?? surface) else { return nil }

        let analysis = context.flatMap { analyze(surface: surface, in: $0) }
        let partOfSpeech = analysis?.partOfSpeech ?? isolatedPartOfSpeech(surface)
        let surfaceKey = VocabularyTextPolicy.canonicalVocabularyKey(surface)
        let lemmaKey = VocabularyTextPolicy.canonicalVocabularyKey(lemma)
        let isBaseForm = surfaceKey == lemmaKey

        switch partOfSpeech {
        case "Verb":
            if isBaseForm { return .grundform }
            // Morphology comes first, because it is decisive: an -ing form and a
            // lemma+s form cannot be past participles no matter what precedes
            // them. Testing the auxiliary first mislabeled "she looks" as a
            // participle whenever a copular "is"/"was" appeared earlier in the
            // clause.
            if surfaceKey.hasSuffix("ing") { return .presentParticiple }
            if isThirdPersonSingular(surfaceKey: surfaceKey, lemmaKey: lemmaKey) {
                return .thirdPersonSingular
            }
            // An auxiliary in the clause proves the participle.
            if analysis?.hasClauseAuxiliary == true { return .pastParticiple }
            // Past tense and attributive participle are indistinguishable here
            // ("walked" vs "the completed work"), so report the honest coarse
            // label rather than claiming a tense that may be wrong.
            return .finiteVerb
        case "Noun":
            if isBaseForm { return .grundform }
            // English nouns have no case system, so a noun whose surface differs
            // from its lemma is a plural — the tagger resolves even the
            // irregulars ("children" → "child", "mice" → "mouse"). Possessives
            // are the one other way a noun can differ, so they are excluded.
            return isPossessive(surface) ? nil : .plural
        default:
            return isBaseForm ? .grundform : nil
        }
    }

    /// Whether `surfaceKey` is the lemma's third person singular. Only the
    /// regular spellings are claimed; anything else falls through.
    private static func isThirdPersonSingular(surfaceKey: String, lemmaKey: String) -> Bool {
        guard !lemmaKey.isEmpty else { return false }
        if surfaceKey == lemmaKey + "s" || surfaceKey == lemmaKey + "es" { return true }
        // study -> studies, carry -> carries
        if lemmaKey.hasSuffix("y") {
            return surfaceKey == lemmaKey.dropLast() + "ies"
        }
        return false
    }

    private static func isPossessive(_ surface: String) -> Bool {
        surface.contains("'") || surface.contains("’")
    }

    // MARK: - Tagging

    private struct ContextAnalysis {
        let partOfSpeech: String?
        /// True when a form of have/be governs this token earlier in the clause
        /// — "has written", "was carefully written", "had already walked".
        let hasClauseAuxiliary: Bool
    }

    private static func analyze(surface: String, in context: String) -> ContextAnalysis? {
        let text = VocabularyTextPolicy.normalizedVocabularyText(context)
        guard !text.isEmpty else { return nil }

        let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
        tagger.string = text
        let range = text.startIndex..<text.endIndex
        tagger.setLanguage(.english, range: range)

        // Punctuation is kept: it marks the clause boundary the backward search
        // must not cross.
        var tokens: [(surface: String, lemma: String, partOfSpeech: String)] = []
        tagger.enumerateTags(
            in: range,
            unit: .word,
            scheme: .lemma,
            options: [.omitWhitespace]
        ) { tag, tokenRange in
            let token = String(text[tokenRange])
            let partOfSpeech = tagger.tag(
                at: tokenRange.lowerBound,
                unit: .word,
                scheme: .lexicalClass
            ).0?.rawValue ?? ""
            tokens.append((token, tag?.rawValue ?? token, partOfSpeech))
            return true
        }

        let target = VocabularyTextPolicy.canonicalVocabularyKey(surface)
        guard let index = tokens.firstIndex(where: {
            VocabularyTextPolicy.canonicalVocabularyKey($0.surface) == target
        }) else {
            return nil
        }

        // English keeps the auxiliary before the participle, so only a backward
        // search is needed — and only within this clause, so "He is tired and
        // walked home" does not read `is` as governing `walked`.
        var precedingAuxiliary = false
        for token in tokens[..<index].reversed() {
            if clauseBarriers.contains(token.partOfSpeech) { break }
            if token.partOfSpeech == "Verb",
               auxiliaryLemmas.contains(VocabularyTextPolicy.canonicalVocabularyKey(token.lemma)) {
                precedingAuxiliary = true
                break
            }
        }

        return ContextAnalysis(
            partOfSpeech: tokens[index].partOfSpeech.isEmpty ? nil : tokens[index].partOfSpeech,
            hasClauseAuxiliary: precedingAuxiliary
        )
    }

    private static func isEnglish(_ text: String) -> Bool {
        let value = VocabularyTextPolicy.normalizedVocabularyText(text)
        guard !value.isEmpty else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(value)
        return recognizer.dominantLanguage == .english
    }

    private static func isolatedPartOfSpeech(_ word: String) -> String? {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = word
        let range = word.startIndex..<word.endIndex
        tagger.setLanguage(.english, range: range)
        return tagger.tag(at: word.startIndex, unit: .word, scheme: .lexicalClass).0?.rawValue
    }
}
