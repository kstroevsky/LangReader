import Foundation

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

/// Compatibility names retained while the historical German-specific cache
/// surfaces are migrated to the provider-neutral form-label boundary.
package typealias GermanFormLabelEvidence = VocabularyFormLabelEvidence
package typealias GermanFormLabelResolution = VocabularyFormLabelResolution

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
    package static let labelingVersion = 4

    private static let auxiliaryLemmas: Set<String> = ["haben", "sein", "werden"]
    private static let umlauts = CharacterSet(charactersIn: "äöüÄÖÜ")
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
        context: String? = nil,
        evidenceProvider: @escaping VocabularyFormLabelEvidenceProvider = { _ in .unavailable }
    ) -> GermanFormLabel? {
        resolution(
            surfaceForm: rawSurface,
            lemma: rawLemma,
            context: context,
            evidenceProvider: evidenceProvider
        ).label
    }

    /// Resolves a label and records whether the verdict consumed sentence-level
    /// NLP evidence. The language-specific router is the sole language owner;
    /// once it chooses this labeler, a token-level recognizer cannot veto it.
    package static func resolution(
        surfaceForm rawSurface: String,
        lemma rawLemma: String,
        context: String? = nil,
        evidenceProvider: @escaping VocabularyFormLabelEvidenceProvider = { _ in .unavailable }
    ) -> GermanFormLabelResolution {
        let surface = VocabularyTextPolicy.normalizedVocabularyText(rawSurface)
        let lemma = VocabularyTextPolicy.normalizedVocabularyText(rawLemma)
        guard VocabularyTextPolicy.isSingleVocabularyWord(surface), !lemma.isEmpty else {
            return .contextIndependent(nil)
        }
        let isBaseForm = VocabularyTextPolicy.canonicalVocabularyKey(surface)
            == VocabularyTextPolicy.canonicalVocabularyKey(lemma)

        // The owned bypass is deliberately narrower than the general plural
        // heuristic below. Capitalization plus a stem-matching umlaut `-er`
        // alternation (`Buch` -> `Bücher`) is precise on the pinned German
        // development corpus; ordinary `-en`/`-n` endings overlap singular weak
        // noun declension and still require Apple or flexion evidence.
        if isNounLikeLemma(lemma), isHighConfidenceOwnedPlural(surface: surface, lemma: lemma) {
            return .contextIndependent(.plural)
        }

        let evidence = evidenceProvider(VocabularyFormLabelEvidenceRequest(
            surface: surface,
            context: context,
            language: .german,
            auxiliaryLemmas: auxiliaryLemmas,
            allowsTrailingAuxiliary: true
        ))
        let label: GermanFormLabel?
        switch evidence.partOfSpeech {
        case "Verb":
            if isBaseForm {
                label = .infinitiv
            } else if evidence.hasClauseAuxiliary {
                label = .partizipII
            } else {
                label = .finiteVerb
            }
        case "Noun":
            if isBaseForm {
                label = .grundform
            } else {
                label = isPlural(surface: surface, lemma: lemma) ? .plural : nil
            }
        default:
            // Missing/unknown POS is not evidence that an identity surface is a
            // grammatical base form. A host without the language model must
            // abstain instead of turning the retained surface into knowledge.
            label = nil
        }
        return .contextual(label)
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

    private static func isHighConfidenceOwnedPlural(surface: String, lemma: String) -> Bool {
        guard gainsUmlaut(surface: surface, lemma: lemma) else { return false }
        let surfaceKey = VocabularyTextPolicy.canonicalVocabularyKey(surface)
        let lemmaKey = VocabularyTextPolicy.canonicalVocabularyKey(lemma)
        guard surfaceKey.hasSuffix("er") else { return false }
        return foldGermanUmlauts(String(surfaceKey.dropLast(2))) == foldGermanUmlauts(lemmaKey)
    }

    private static func foldGermanUmlauts(_ value: String) -> String {
        value
            .replacingOccurrences(of: "ä", with: "a")
            .replacingOccurrences(of: "ö", with: "o")
            .replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: "ß", with: "ss")
    }

    private static func isNounLikeLemma(_ lemma: String) -> Bool {
        lemma.first(where: \Character.isLetter)?.isUppercase == true
    }

}
