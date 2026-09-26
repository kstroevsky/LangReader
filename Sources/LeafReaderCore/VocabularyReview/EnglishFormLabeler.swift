import Foundation

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
package enum EnglishFormLabeler {
    /// Bumped whenever the heuristics in this file change, so labels persisted
    /// by an older ruleset are treated as absent. Shares the cache table with
    /// the German labeler, which is why the two versions move independently.
    package static let labelingVersion = 1

    /// Auxiliaries that prove a following/preceding participle.
    private static let auxiliaryLemmas: Set<String> = ["have", "be"]
    /// Labels `surfaceForm` given its lemma, optionally using the sentence it
    /// appeared in.
    ///
    /// Context is what separates a past participle from any other past form:
    /// "has walked" is a participle, "walked" alone is not provably one.
    package static func label(
        surfaceForm rawSurface: String,
        lemma rawLemma: String,
        context: String? = nil,
        evidenceProvider: @escaping VocabularyFormLabelEvidenceProvider = { _ in .unavailable }
    ) -> WordFormLabel? {
        resolution(
            surfaceForm: rawSurface,
            lemma: rawLemma,
            context: context,
            evidenceProvider: evidenceProvider
        ).label
    }

    package static func resolution(
        surfaceForm rawSurface: String,
        lemma rawLemma: String,
        context: String? = nil,
        evidenceProvider: @escaping VocabularyFormLabelEvidenceProvider = { _ in .unavailable }
    ) -> VocabularyFormLabelResolution {
        let surface = VocabularyTextPolicy.normalizedVocabularyText(rawSurface)
        let lemma = VocabularyTextPolicy.normalizedVocabularyText(rawLemma)
        guard VocabularyTextPolicy.isSingleVocabularyWord(surface), !lemma.isEmpty else {
            return .contextIndependent(nil)
        }

        let evidence = evidenceProvider(VocabularyFormLabelEvidenceRequest(
            surface: surface,
            context: context,
            language: .english,
            auxiliaryLemmas: auxiliaryLemmas,
            allowsTrailingAuxiliary: false
        ))
        let surfaceKey = VocabularyTextPolicy.canonicalVocabularyKey(surface)
        let lemmaKey = VocabularyTextPolicy.canonicalVocabularyKey(lemma)
        let isBaseForm = surfaceKey == lemmaKey

        let label: WordFormLabel?
        switch evidence.partOfSpeech {
        case "Verb":
            if isBaseForm {
                label = .grundform
            // Morphology comes first, because it is decisive: an -ing form and a
            // lemma+s form cannot be past participles no matter what precedes
            // them. Testing the auxiliary first mislabeled "she looks" as a
            // participle whenever a copular "is"/"was" appeared earlier in the
            // clause.
            } else if surfaceKey.hasSuffix("ing") {
                label = .presentParticiple
            } else if isThirdPersonSingular(surfaceKey: surfaceKey, lemmaKey: lemmaKey) {
                label = .thirdPersonSingular
            // An auxiliary in the clause proves the participle.
            } else if evidence.hasClauseAuxiliary {
                label = .pastParticiple
            // Past tense and attributive participle are indistinguishable here
            // ("walked" vs "the completed work"), so report the honest coarse
            // label rather than claiming a tense that may be wrong.
            } else {
                label = .finiteVerb
            }
        case "Noun":
            if isBaseForm {
                label = .grundform
            // English nouns have no case system, so a noun whose surface differs
            // from its lemma is a plural — the tagger resolves even the
            // irregulars ("children" → "child", "mice" → "mouse"). Possessives
            // are the one other way a noun can differ, so they are excluded.
            } else {
                label = isPossessive(surface) ? nil : .plural
            }
        default:
            label = nil
        }
        return .contextual(label)
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

}
