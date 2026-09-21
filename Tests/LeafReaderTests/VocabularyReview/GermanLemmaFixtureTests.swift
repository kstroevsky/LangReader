import Foundation
import NaturalLanguage
import LeafReaderCore

// Optional strict characterization for Apple's German NLP runtime.
//
// These cases do not define portable LeafReader behavior. By default they record
// drift without failing the product suite; set
// LEAFREADER_STRICT_NL_CHARACTERIZATION=1 to pin one host runtime deliberately.
//
// Two groups, deliberately separated:
//   * baseline  — correct today, must stay correct.
//   * knownGaps — wrong today, pinned on purpose. When a later tier fixes one
//                 of these, the assertion fails and must be moved to baseline.
enum GermanLemmaFixtureTests {

    // MARK: - Helpers

    private static let strictCharacterization =
        ProcessInfo.processInfo.environment["LEAFREADER_STRICT_NL_CHARACTERIZATION"] == "1"

    private static func characterizeEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ message: String
    ) throws {
        guard actual != expected else { return }
        if strictCharacterization {
            try expectEqual(actual, expected, message)
        } else {
            print(
                "NaturalLanguage characterization drift: \(message); "
                    + "expected \(String(describing: expected)), got \(String(describing: actual))"
            )
        }
    }

    private static func characterizedValue<T>(_ value: T?, _ message: String) throws -> T? {
        guard value == nil else { return value }
        if strictCharacterization {
            throw TestFailure(description: message)
        }
        print("NaturalLanguage characterization drift: \(message)")
        return nil
    }

    /// Part of speech for a word tagged in isolation.
    private static func isolatedPartOfSpeech(_ word: String) -> String? {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = word
        let range = word.startIndex..<word.endIndex
        tagger.setLanguage(.german, range: range)
        return tagger.tag(at: word.startIndex, unit: .word, scheme: .lexicalClass).0?.rawValue
    }

    /// Lemma and part of speech for `target` as tagged *inside* a sentence, so
    /// the tagger has the surrounding context it needs to disambiguate.
    private static func inSentence(
        _ sentence: String,
        target: String
    ) -> (lemma: String, partOfSpeech: String)? {
        let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
        tagger.string = sentence
        let range = sentence.startIndex..<sentence.endIndex
        tagger.setLanguage(.german, range: range)

        var result: (String, String)?
        tagger.enumerateTags(
            in: range,
            unit: .word,
            scheme: .lemma,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, tokenRange in
            guard String(sentence[tokenRange]) == target else { return true }
            let lemma = tag?.rawValue ?? String(sentence[tokenRange])
            let pos = tagger.tag(
                at: tokenRange.lowerBound,
                unit: .word,
                scheme: .lexicalClass
            ).0?.rawValue ?? "<none>"
            result = (lemma, pos)
            return false
        }
        return result
    }

    // MARK: - Baseline: works today, must keep working

    static func testVerbInflectionBaseline() throws {
        // Partizip II and Präteritum both resolve correctly in isolation.
        // This is the strongest part of the current behavior and the reason
        // verb form labeling can ship without any dictionary lookup.
        let cases: [(surface: String, lemma: String)] = [
            ("gegangen", "gehen"),
            ("ging", "gehen"),
            ("gesprochen", "sprechen"),
            ("sprach", "sprechen"),
            ("gelaufen", "laufen"),
            ("lief", "laufen"),
            ("gegessen", "essen"),
            ("genommen", "nehmen"),
            ("nahm", "nehmen"),
            ("geschrieben", "schreiben"),
            ("schrieb", "schreiben"),
            ("gefunden", "finden"),
            ("fand", "finden")
        ]
        for (surface, expected) in cases {
            try characterizeEqual(
                GermanLemmaResolver.lemma(for: surface, language: .german),
                expected,
                "German verb '\(surface)' should lemmatize to '\(expected)'"
            )
        }
    }

    static func testVerbInflectionInSentenceBaseline() throws {
        let cases: [(sentence: String, target: String, lemma: String)] = [
            ("Er ist gestern nach Hause gegangen.", "gegangen", "gehen"),
            ("Sie ging langsam nach Hause.", "ging", "gehen"),
            ("Ich habe drei Bücher gelesen.", "gelesen", "lesen"),
            ("Die Kinder liefen schnell.", "liefen", "laufen"),
            ("Er kam gestern spät an.", "kam", "kommen")
        ]
        for (sentence, target, expected) in cases {
            guard let result = try characterizedValue(
                inSentence(sentence, target: target),
                "German tagger should tag '\(target)' in \"\(sentence)\""
            ) else { continue }
            try characterizeEqual(
                result.lemma,
                expected,
                "German verb '\(target)' in context should lemmatize to '\(expected)'"
            )
            try characterizeEqual(
                result.partOfSpeech,
                "Verb",
                "German verb '\(target)' in context should be tagged as a Verb"
            )
        }
    }

    static func testNounPluralBaseline() throws {
        // Irregular plurals resolve through the system lemma model.
        let cases: [(surface: String, lemma: String)] = [
            ("Bücher", "Buch"),
            ("Häuser", "Haus"),
            ("Kinder", "Kind"),
            ("Männer", "Mann"),
            ("Wörter", "Wort"),
            ("Länder", "Land")
        ]
        for (surface, expected) in cases {
            try characterizeEqual(
                GermanLemmaResolver.lemma(for: surface, language: .german),
                expected,
                "German plural '\(surface)' should lemmatize to '\(expected)'"
            )
        }
    }

    static func testNounVerbDisambiguationBaseline() throws {
        // Context does separate most noun/verb homographs. This is the part of
        // the POS signal that is trustworthy enough to display.
        let cases: [(sentence: String, target: String, pos: String)] = [
            ("Das Essen ist sehr gut.", "Essen", "Noun"),
            ("Wir essen jeden Tag Brot.", "essen", "Verb"),
            ("Die Arbeiten sind fertig.", "Arbeiten", "Noun"),
            ("Wir arbeiten jeden Tag.", "arbeiten", "Verb"),
            ("Die Reise war sehr lang.", "Reise", "Noun")
        ]
        for (sentence, target, expected) in cases {
            guard let result = try characterizedValue(
                inSentence(sentence, target: target),
                "German tagger should tag '\(target)' in \"\(sentence)\""
            ) else { continue }
            try characterizeEqual(
                result.partOfSpeech,
                expected,
                "German word '\(target)' in \"\(sentence)\" should be tagged \(expected)"
            )
        }
    }

    // MARK: - Known gaps: wrong today, pinned deliberately

    static func testKnownLemmaGaps() throws {
        // The nominalized infinitive 'das Essen' lemmatizes to 'Esse' (a forge),
        // which is a different word entirely. POS is correct here; the lemma is not.
        guard let essen = try characterizedValue(
            inSentence("Das Essen ist sehr gut.", target: "Essen"),
            "German tagger should tag 'Essen'"
        ) else { return }
        try characterizeEqual(
            essen.lemma,
            "Esse",
            "KNOWN GAP: nominalized 'Essen' lemmatizes to the unrelated noun 'Esse'"
        )
    }

    static func testKnownPartOfSpeechGaps() throws {
        // A finite verb tagged as an Adverb. This is the measured misfire that
        // disqualifies the POS tag from being part of the storage grouping key:
        // it is wrong roughly 1 in 6 for noun/verb homographs, and it fails silently.
        guard let reise = try characterizedValue(
            inSentence("Ich reise nach Berlin.", target: "reise"),
            "German tagger should tag 'reise'"
        ) else { return }
        try characterizeEqual(
            reise.partOfSpeech,
            "Adverb",
            "KNOWN GAP: finite verb 'reise' is mis-tagged as an Adverb"
        )

        // Predicate adjectives are systematically tagged Adverb. This does not
        // affect noun/verb grouping, but it means the raw POS tag must never be
        // shown to the user as a grammatical label without correction.
        for (sentence, target) in [
            ("Die Häuser in der Stadt sind alt.", "alt"),
            ("Die Reise war sehr lang.", "lang")
        ] {
            guard let result = try characterizedValue(
                inSentence(sentence, target: target),
                "German tagger should tag '\(target)'"
            ) else { continue }
            try characterizeEqual(
                result.partOfSpeech,
                "Adverb",
                "KNOWN GAP: predicate adjective '\(target)' is tagged Adverb, not Adjective"
            )
        }

        // 'aßen' in isolation lemmatizes correctly but is tagged Adjective,
        // confirming that isolated-word POS is unreliable and context is required.
        try characterizeEqual(
            GermanLemmaResolver.lemma(for: "aßen", language: .german),
            "essen",
            "isolated 'aßen' still lemmatizes correctly"
        )
        try characterizeEqual(
            isolatedPartOfSpeech("aßen"),
            "Adjective",
            "KNOWN GAP: isolated verb form 'aßen' is tagged Adjective"
        )
    }

    static func testSeparableVerbGap() throws {
        // Separable verbs are not reassembled: 'stehe ... auf' yields 'stehen'
        // plus a stray particle, never 'aufstehen'. Accepted for v1 — these
        // occurrences file under the base verb.
        guard let stehe = try characterizedValue(
                  inSentence("Ich stehe jeden Morgen früh auf.", target: "stehe"),
                  "German tagger should tag separable verb part 'stehe'"
              ),
              let auf = try characterizedValue(
                  inSentence("Ich stehe jeden Morgen früh auf.", target: "auf"),
                  "German tagger should tag separable verb part 'auf'"
              ) else { return }
        try characterizeEqual(
            stehe.lemma,
            "stehen",
            "KNOWN GAP: separable 'aufstehen' reduces to the base verb 'stehen'"
        )
        try characterizeEqual(
            auf.partOfSpeech,
            "Particle",
            "KNOWN GAP: the separated prefix 'auf' is left as a bare Particle"
        )
    }
}
