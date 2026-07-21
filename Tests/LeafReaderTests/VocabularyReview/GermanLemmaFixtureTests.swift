import Foundation
import NaturalLanguage

// T0 baseline characterization for German lemmatization.
//
// These tests do not describe desired behavior — they describe what the macOS
// NaturalLanguage tagger does *today*, so that later tiers (form labeling,
// Wiktionary flexion lookup) cannot silently regress what already works, and
// so that the known gaps fail loudly the moment they are fixed.
//
// Two groups, deliberately separated:
//   * baseline  — correct today, must stay correct.
//   * knownGaps — wrong today, pinned on purpose. When a later tier fixes one
//                 of these, the assertion fails and must be moved to baseline.
enum GermanLemmaFixtureTests {

    // MARK: - Helpers

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
            try expectEqual(
                GermanLemmaResolver.lemma(for: surface),
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
            guard let result = inSentence(sentence, target: target) else {
                throw TestFailure(description: "German tagger should tag '\(target)' in \"\(sentence)\"")
            }
            try expectEqual(
                result.lemma,
                expected,
                "German verb '\(target)' in context should lemmatize to '\(expected)'"
            )
            try expectEqual(
                result.partOfSpeech,
                "Verb",
                "German verb '\(target)' in context should be tagged as a Verb"
            )
        }
    }

    static func testNounPluralBaseline() throws {
        // Most irregular plurals resolve. 'Häuser' does not — see knownGaps.
        let cases: [(surface: String, lemma: String)] = [
            ("Bücher", "Buch"),
            ("Kinder", "Kind"),
            ("Männer", "Mann"),
            ("Wörter", "Wort"),
            ("Länder", "Land")
        ]
        for (surface, expected) in cases {
            try expectEqual(
                GermanLemmaResolver.lemma(for: surface),
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
            guard let result = inSentence(sentence, target: target) else {
                throw TestFailure(description: "German tagger should tag '\(target)' in \"\(sentence)\"")
            }
            try expectEqual(
                result.partOfSpeech,
                expected,
                "German word '\(target)' in \"\(sentence)\" should be tagged \(expected)"
            )
        }
    }

    // MARK: - Known gaps: wrong today, pinned deliberately

    static func testKnownLemmaGaps() throws {
        // 'Häuser' fails to reduce to 'Haus' both in isolation and in context.
        // The Wiktionary flexion table for 'Haus' lists 'Nominativ Plural=Häuser',
        // so the dictionary tier is expected to fix this. When it does, move
        // this case into testNounPluralBaseline.
        try expectEqual(
            GermanLemmaResolver.lemma(for: "Häuser"),
            "Häuser",
            "KNOWN GAP: 'Häuser' does not currently reduce to 'Haus'"
        )

        // The nominalized infinitive 'das Essen' lemmatizes to 'Esse' (a forge),
        // which is a different word entirely. POS is correct here; the lemma is not.
        guard let essen = inSentence("Das Essen ist sehr gut.", target: "Essen") else {
            throw TestFailure(description: "German tagger should tag 'Essen'")
        }
        try expectEqual(
            essen.lemma,
            "Esse",
            "KNOWN GAP: nominalized 'Essen' lemmatizes to the unrelated noun 'Esse'"
        )
    }

    static func testKnownPartOfSpeechGaps() throws {
        // A finite verb tagged as an Adverb. This is the measured misfire that
        // disqualifies the POS tag from being part of the storage grouping key:
        // it is wrong roughly 1 in 6 for noun/verb homographs, and it fails silently.
        guard let reise = inSentence("Ich reise nach Berlin.", target: "reise") else {
            throw TestFailure(description: "German tagger should tag 'reise'")
        }
        try expectEqual(
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
            guard let result = inSentence(sentence, target: target) else {
                throw TestFailure(description: "German tagger should tag '\(target)'")
            }
            try expectEqual(
                result.partOfSpeech,
                "Adverb",
                "KNOWN GAP: predicate adjective '\(target)' is tagged Adverb, not Adjective"
            )
        }

        // 'aßen' in isolation lemmatizes correctly but is tagged Adjective,
        // confirming that isolated-word POS is unreliable and context is required.
        try expectEqual(
            GermanLemmaResolver.lemma(for: "aßen"),
            "essen",
            "isolated 'aßen' still lemmatizes correctly"
        )
        try expectEqual(
            isolatedPartOfSpeech("aßen"),
            "Adjective",
            "KNOWN GAP: isolated verb form 'aßen' is tagged Adjective"
        )
    }

    static func testSeparableVerbGap() throws {
        // Separable verbs are not reassembled: 'stehe ... auf' yields 'stehen'
        // plus a stray particle, never 'aufstehen'. Accepted for v1 — these
        // occurrences file under the base verb.
        guard let stehe = inSentence("Ich stehe jeden Morgen früh auf.", target: "stehe"),
              let auf = inSentence("Ich stehe jeden Morgen früh auf.", target: "auf") else {
            throw TestFailure(description: "German tagger should tag the separable verb parts")
        }
        try expectEqual(
            stehe.lemma,
            "stehen",
            "KNOWN GAP: separable 'aufstehen' reduces to the base verb 'stehen'"
        )
        try expectEqual(
            auf.partOfSpeech,
            "Particle",
            "KNOWN GAP: the separated prefix 'auf' is left as a bare Particle"
        )
    }
}
