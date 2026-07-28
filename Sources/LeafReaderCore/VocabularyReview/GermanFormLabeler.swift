import Foundation
import NaturalLanguage
import LeafReaderCore

/// A grammatical form label for an observed German surface form.
///
/// Labels are deliberately coarse. The offline tagger can prove some
/// distinctions and not others, so this type only encodes what is
/// measurably reliable; the Wiktionary flexion tier refines
/// `.finiteVerb` into Präsens/Präteritum and `.plural` into a specific case.
package enum GermanFormLabel: String, Equatable {
    /// Surface form equals the lemma and is a verb: `gehen`.
    case infinitiv
    /// Past participle, proven by an auxiliary in the same clause: `gegangen`.
    case partizipII
    /// A conjugated verb form that is either Präsens or Präteritum. The
    /// offline tagger cannot separate the two — `bat`, `hielt` and `galt` are
    /// Präteritum yet end in `-t` like a Präsens third person — so both are
    /// reported under one honest label until the dictionary tier resolves it.
    case finiteVerb
    /// Present tense, resolved from a Wiktionary flexion table.
    case praesens
    /// Simple past, resolved from a Wiktionary flexion table.
    case praeteritum
    /// Noun plural, proven by umlaut alternation or an unambiguous plural ending.
    case plural
    /// Surface form equals the lemma: `Haus`.
    case grundform
    /// English past participle, proven by an auxiliary in the same clause:
    /// `has written`. Reported separately from `.partizipII` so each language
    /// keeps its own terminology.
    case pastParticiple
    /// English `-ing` form, proven morphologically: `running`.
    case presentParticiple
    /// English third person singular, proven morphologically: `walks`, `goes`.
    case thirdPersonSingular

    /// Whether this label tells the reader something they could not see for
    /// themselves. `.grundform` only earns its place alongside inflected forms
    /// — on its own it restates the headword, which on real documents accounts
    /// for the majority of labels and reads as noise.
    package var isInformative: Bool {
        self != .grundform
    }

    package var displayName: String {
        switch self {
        case .infinitiv:
            return AppText.localized("原形 (Infinitiv)", "Infinitiv")
        case .partizipII:
            return AppText.localized("第二分词 (Partizip II)", "Partizip II")
        case .finiteVerb:
            return AppText.localized("变位形式", "Conjugated form")
        case .praesens:
            return AppText.localized("现在时 (Präsens)", "Präsens")
        case .praeteritum:
            return AppText.localized("过去时 (Präteritum)", "Präteritum")
        case .plural:
            return AppText.localized("复数 (Plural)", "Plural")
        case .grundform:
            return AppText.localized("原形", "Base form")
        case .pastParticiple:
            return AppText.localized("过去分词", "Past participle")
        case .presentParticiple:
            return AppText.localized("现在分词 (-ing)", "-ing form")
        case .thirdPersonSingular:
            return AppText.localized("第三人称单数", "3rd person singular")
        }
    }
}

/// The label type is shared by every language's labeler; the `German` prefix is
/// historical (it predates the other languages and is baked into the persisted
/// cache's rawValues). New code should prefer this name.
package typealias WordFormLabel = GermanFormLabel

/// Derives a grammatical form label for a German surface form, offline.
///
/// The guiding rule is **never guess**: every heuristic here was measured
/// against a labeled corpus and tuned for zero false positives, accepting
/// misses instead. A `nil` label means "unknown", which the UI shows as an
/// unlabeled form rather than an incorrect one.
package enum GermanFormLabeler {
    /// Bumped whenever the offline heuristics in this file change. A label
    /// persisted by an older ruleset carries an older version and is treated as
    /// absent, so a labeler improvement takes effect without a manual cache wipe.
    package static let labelingVersion = 1

    private static let auxiliaryLemmas: Set<String> = ["haben", "sein", "werden"]
    private static let umlauts = CharacterSet(charactersIn: "äöüÄÖÜ")
    /// Token classes that end the clause an auxiliary can govern.
    private static let clauseBarriers: Set<String> = [
        "Conjunction", "Punctuation", "SentenceTerminator"
    ]

    /// Labels `surfaceForm` given its lemma, optionally using the sentence it
    /// appeared in.
    ///
    /// Context materially changes what can be determined. Partizip II is only
    /// detectable with context: morphology alone mislabels `geht`, `gehört`
    /// and `gewinnt` as participles while missing `verstanden`, `besucht` and
    /// `studiert`, which carry no `ge-` prefix.
    package static func label(
        surfaceForm rawSurface: String,
        lemma rawLemma: String,
        context: String? = nil
    ) -> GermanFormLabel? {
        let surface = VocabularyTextPolicy.normalizedVocabularyText(rawSurface)
        let lemma = VocabularyTextPolicy.normalizedVocabularyText(rawLemma)
        guard VocabularyTextPolicy.isSingleEnglishWord(surface), !lemma.isEmpty else {
            return nil
        }
        // The app has no explicit German mode — the German dictionary is a
        // fallback for words the English dictionary misses — so the labeler has
        // to decide for itself. Without this gate an English document would show
        // German grammatical labels.
        guard isGerman(context ?? surface) else { return nil }

        let analysis = context.flatMap { analyze(surface: surface, in: $0) }
        let partOfSpeech = analysis?.partOfSpeech ?? isolatedPartOfSpeech(surface)
        let isBaseForm = VocabularyTextPolicy.canonicalVocabularyKey(surface)
            == VocabularyTextPolicy.canonicalVocabularyKey(lemma)

        switch partOfSpeech {
        case "Verb":
            if isBaseForm { return .infinitiv }
            if analysis?.hasClauseAuxiliary == true { return .partizipII }
            return .finiteVerb
        case "Noun":
            if isBaseForm { return .grundform }
            return isPlural(surface: surface, lemma: lemma) ? .plural : nil
        default:
            // Adjectives are systematically tagged Adverb by the German tagger,
            // so no adjective-specific label can be trusted here.
            return isBaseForm ? .grundform : nil
        }
    }

    // MARK: - Noun number

    /// Conservative plural test: measured at zero false positives.
    ///
    /// Rejects the singular forms that merely differ from the lemma —
    /// genitive `Hauses`, dative `Hause` — and accepts only umlaut alternation
    /// or a plural ending on an otherwise changed stem. `Autos` and `Tische`
    /// are deliberately declined: they are equally valid genitive and dative
    /// singulars, and only a paradigm can disambiguate them.
    private static func isPlural(surface: String, lemma: String) -> Bool {
        let s = VocabularyTextPolicy.canonicalVocabularyKey(surface)
        let l = VocabularyTextPolicy.canonicalVocabularyKey(lemma)
        guard s != l, !s.isEmpty, !l.isEmpty else { return false }

        if gainsUmlaut(surface: surface, lemma: lemma) { return true }
        // Genitive singular (Haus -> Hauses) and dative singular (Haus -> Hause)
        // add an ending without otherwise changing the stem.
        if s == l + "s" || s == l + "es" || s == l + "e" { return false }
        return s.hasSuffix("er") || s.hasSuffix("en") || s.hasSuffix("n")
            || s.hasSuffix("s") || s.hasSuffix("e")
    }

    private static func gainsUmlaut(surface: String, lemma: String) -> Bool {
        let surfaceHasUmlaut = surface.unicodeScalars.contains { umlauts.contains($0) }
        let lemmaHasUmlaut = lemma.unicodeScalars.contains { umlauts.contains($0) }
        return surfaceHasUmlaut && !lemmaHasUmlaut
    }

    // MARK: - Tagging

    private struct ContextAnalysis {
        let partOfSpeech: String?
        /// True when a form of haben/sein/werden governs this token — either
        /// earlier in the sentence (`ist … gegangen`) or immediately after it,
        /// which is where German verb-final clauses put it (`weil er gegangen ist`).
        let hasClauseAuxiliary: Bool
    }

    private static func analyze(surface: String, in context: String) -> ContextAnalysis? {
        let text = VocabularyTextPolicy.normalizedVocabularyText(context)
        guard !text.isEmpty else { return nil }

        let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
        tagger.string = text
        let range = text.startIndex..<text.endIndex
        tagger.setLanguage(.german, range: range)

        // Punctuation is deliberately kept: commas and sentence terminators act
        // as clause barriers when searching backwards for an auxiliary.
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

        func isAuxiliary(_ token: (surface: String, lemma: String, partOfSpeech: String)) -> Bool {
            token.partOfSpeech == "Verb"
                && auxiliaryLemmas.contains(
                    VocabularyTextPolicy.canonicalVocabularyKey(token.lemma)
                )
        }

        // Search backwards only as far as the current clause. Scanning the whole
        // sentence would misread "Er ist müde und lief schnell", where `ist`
        // belongs to a different clause than `lief`.
        var precedingAuxiliary = false
        for token in tokens[..<index].reversed() {
            if clauseBarriers.contains(token.partOfSpeech) { break }
            if isAuxiliary(token) {
                precedingAuxiliary = true
                break
            }
        }
        // Only the immediately following token counts for the verb-final case
        // ("weil er gegangen ist"), where German pushes the auxiliary to the end.
        let trailingAuxiliary = tokens.indices.contains(index + 1) && isAuxiliary(tokens[index + 1])

        return ContextAnalysis(
            partOfSpeech: tokens[index].partOfSpeech.isEmpty ? nil : tokens[index].partOfSpeech,
            hasClauseAuxiliary: precedingAuxiliary || trailingAuxiliary
        )
    }

    /// Whether `text` reads as German. Measured at 14/14 on sentence-length and
    /// single-word samples, so it is safe to apply to short PDF contexts.
    private static func isGerman(_ text: String) -> Bool {
        let value = VocabularyTextPolicy.normalizedVocabularyText(text)
        guard !value.isEmpty else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(value)
        return recognizer.dominantLanguage == .german
    }

    private static func isolatedPartOfSpeech(_ word: String) -> String? {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = word
        let range = word.startIndex..<word.endIndex
        tagger.setLanguage(.german, range: range)
        return tagger.tag(at: word.startIndex, unit: .word, scheme: .lexicalClass).0?.rawValue
    }
}
