import Foundation
import LeafReaderCore

// T1 tests for GermanFormLabeler.
//
// The labeling rules were chosen by measuring candidate heuristics against a
// labeled corpus and keeping the one with zero false positives. These tests
// encode both halves of that result: the forms that must be labeled, and —
// just as importantly — the forms that must be left unlabeled rather than
// labeled wrongly.
enum GermanFormLabelerTests {

    private static func label(
        _ surface: String,
        _ lemma: String,
        _ context: String? = nil,
        partOfSpeech: String? = nil,
        hasClauseAuxiliary: Bool = false
    ) -> GermanFormLabel? {
        GermanFormLabeler.resolution(
            surfaceForm: surface,
            lemma: lemma,
            context: context,
            evidenceProvider: { _, _ in
                GermanFormLabelEvidence(
                    partOfSpeech: partOfSpeech,
                    hasClauseAuxiliary: hasClauseAuxiliary
                )
            }
        ).label
    }

    // MARK: - Partizip II

    static func testPartizipIIWithAuxiliary() throws {
        let cases: [(surface: String, lemma: String, sentence: String)] = [
            ("gegangen", "gehen", "Er ist gestern nach Hause gegangen."),
            ("gelesen", "lesen", "Ich habe drei Bücher gelesen."),
            ("gesprochen", "sprechen", "Sie hat laut gesprochen."),
            ("gemacht", "machen", "Das Essen wurde schon gemacht."),
            // No ge- prefix: morphology alone misses all of these.
            ("verstanden", "verstehen", "Er hat die Aufgabe verstanden."),
            ("besucht", "besuchen", "Sie hat uns besucht."),
            ("studiert", "studieren", "Ich habe Medizin studiert."),
            ("zerbrochen", "zerbrechen", "Er hat das Fenster zerbrochen.")
        ]
        for (surface, lemma, sentence) in cases {
            try expectEqual(
                label(surface, lemma, sentence, partOfSpeech: "Verb", hasClauseAuxiliary: true),
                .partizipII,
                "'\(surface)' in \"\(sentence)\" should be labeled Partizip II"
            )
        }
    }

    static func testPartizipIIInVerbFinalClause() throws {
        // German subordinate clauses put the auxiliary after the participle.
        try expectEqual(
            label(
                "gegangen",
                "gehen",
                "Ich weiß, dass er nach Hause gegangen ist.",
                partOfSpeech: "Verb",
                hasClauseAuxiliary: true
            ),
            .partizipII,
            "a verb-final clause should still resolve Partizip II from the trailing auxiliary"
        )
    }

    static func testAuxiliaryInAnotherClauseIsNotBorrowed() throws {
        // The guard that forced the clause-barrier scan: 'ist' belongs to the
        // clause before 'und', so it must not license a Partizip II reading of
        // 'lief', which is Präteritum.
        try expectEqual(
            label("lief", "laufen", "Er ist müde und lief schnell.", partOfSpeech: "Verb"),
            .finiteVerb,
            "an auxiliary in a preceding coordinate clause must not label 'lief' as Partizip II"
        )
        try expectEqual(
            label("ging", "gehen", "Sie war krank, aber sie ging zur Arbeit.", partOfSpeech: "Verb"),
            .finiteVerb,
            "an auxiliary before a comma and conjunction must not reach across the boundary"
        )
    }

    static func testMorphologicalLookalikesAreNotPartizipII() throws {
        // These start with 'ge' and end in 't' or 'en' but are not participles.
        // A morphology-only rule labels all three wrongly.
        let cases: [(surface: String, lemma: String, sentence: String)] = [
            ("geht", "gehen", "Er geht jeden Tag zur Schule."),
            ("gehört", "gehören", "Sie gehört zur Familie."),
            ("gewinnt", "gewinnen", "Er gewinnt das Spiel.")
        ]
        for (surface, lemma, sentence) in cases {
            try expectEqual(
                label(surface, lemma, sentence, partOfSpeech: "Verb"),
                .finiteVerb,
                "'\(surface)' looks like a participle but is finite; it must not be labeled Partizip II"
            )
        }
    }

    // MARK: - Other verb forms

    static func testInfinitiveAndFiniteForms() throws {
        try expectEqual(
            label("gehen", "gehen", "Wir wollen nach Hause gehen.", partOfSpeech: "Verb"),
            .infinitiv,
            "a verb equal to its lemma is an Infinitiv"
        )
        // Präteritum forms that end in -t and would fool an ending-based rule.
        for (surface, lemma, sentence) in [
            ("bat", "bitten", "Er bat um Hilfe."),
            ("hielt", "halten", "Sie hielt das Buch."),
            ("machte", "machen", "Er machte seine Arbeit.")
        ] {
            try expectEqual(
                label(surface, lemma, sentence, partOfSpeech: "Verb"),
                .finiteVerb,
                "'\(surface)' is a finite form and must not be split into a guessed tense"
            )
        }
    }

    // MARK: - Nouns

    static func testNounPlurals() throws {
        let cases: [(surface: String, lemma: String, sentence: String)] = [
            ("Bücher", "Buch", "Die Bücher liegen dort."),
            ("Kinder", "Kind", "Die Kinder spielen draußen."),
            ("Männer", "Mann", "Die Männer arbeiten hier."),
            ("Frauen", "Frau", "Die Frauen sprechen laut.")
        ]
        for (surface, lemma, sentence) in cases {
            try expectEqual(
                label(surface, lemma, sentence, partOfSpeech: "Noun"),
                .plural,
                "'\(surface)' should be labeled Plural"
            )
        }
    }

    static func testAmbiguousNounFormsStayUnlabeled() throws {
        // Every one of these differs from its lemma yet is not provably plural.
        // Returning nil is the correct outcome: the UI shows the form without a
        // label rather than asserting something false.
        let cases: [(surface: String, lemma: String, sentence: String, why: String)] = [
            ("Hause", "Haus", "Er geht nach Hause.", "dative singular"),
            ("Hauses", "Haus", "Das Dach des Hauses ist rot.", "genitive singular"),
            ("Autos", "Auto", "Die Autos stehen dort.", "plural and genitive singular are identical"),
            ("Tische", "Tisch", "Die Tische sind neu.", "plural and dative singular are identical")
        ]
        for (surface, lemma, sentence, why) in cases {
            try expectEqual(
                label(surface, lemma, sentence, partOfSpeech: "Noun"),
                nil,
                "'\(surface)' must stay unlabeled (\(why))"
            )
        }
    }

    static func testBaseForms() throws {
        try expectEqual(
            label("Kind", "Kind", "Das Kind spielt.", partOfSpeech: "Noun"),
            .grundform,
            "a noun equal to its lemma is the Grundform"
        )
    }

    static func testOwnedNounMorphologyDoesNotDependOnApplePOS() throws {
        var evidenceRequests = 0
        let plural = GermanFormLabeler.resolution(
            surfaceForm: "Bücher",
            lemma: "Buch",
            context: "Die Bücher liegen dort.",
            evidenceProvider: { _, _ in
                evidenceRequests += 1
                return GermanFormLabelEvidence(partOfSpeech: nil, hasClauseAuxiliary: false)
            }
        )
        try expectEqual(
            plural,
            .contextIndependent(.plural),
            "noun orthography plus conservative morphology should prove Bücher without Apple POS"
        )
        try expectEqual(evidenceRequests, 0, "owned noun morphology should run before Apple evidence")

        let wrongPOS = GermanFormLabeler.resolution(
            surfaceForm: "Bücher",
            lemma: "Buch",
            evidenceProvider: { _, _ in
                GermanFormLabelEvidence(partOfSpeech: "Verb", hasClauseAuxiliary: false)
            }
        )
        try expectEqual(
            wrongPOS,
            .contextIndependent(.plural),
            "a runtime POS disagreement must not veto a proven plural"
        )

        for (surface, lemma) in [
            ("Kunden", "Kunde"),
            ("Herrn", "Herr"),
            ("Präsidenten", "Präsident")
        ] {
            let unresolved = GermanFormLabeler.resolution(
                surfaceForm: surface,
                lemma: lemma,
                evidenceProvider: { _, _ in
                    GermanFormLabelEvidence(partOfSpeech: nil, hasClauseAuxiliary: false)
                }
            )
            try expectEqual(
                unresolved,
                .contextual(nil),
                "capitalization plus an ambiguous weak-noun ending must not prove '\(surface)' plural"
            )
        }
    }

    // MARK: - Guards

    static func testRejectsNonWordInput() throws {
        try expectEqual(label("", "Haus"), nil, "empty surface form yields no label")
        try expectEqual(label("Haus", ""), nil, "empty lemma yields no label")
        try expectEqual(
            label("zwei Wörter", "Wort"),
            nil,
            "a multi-word selection is not a single form"
        )
        try expectEqual(
            label("gehen", "gehen", "Wir gehen nach Hause."),
            nil,
            "missing POS must not turn an unresolved identity lemma into a base-form label"
        )
        try expectEqual(
            label("gehen", "gehen", "Wir gehen nach Hause.", partOfSpeech: "OtherWord"),
            nil,
            "OtherWord POS must abstain"
        )
    }

    static func testMissingContextStillLabelsWhatItCan() throws {
        // Without context Partizip II is undecidable, but owned plural evidence
        // survives, so occurrences lacking stored context still get some labeling.
        try expectEqual(
            label("Bücher", "Buch"),
            .plural,
            "plural detection does not depend on sentence context"
        )
        try expectEqual(
            label("Hause", "Haus", partOfSpeech: "Noun"),
            nil,
            "an ambiguous form stays unlabeled without context too"
        )
    }
}
