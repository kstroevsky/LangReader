import Foundation

// T3 tests for the Wiktionary flexion-table parser.
//
// The fixtures below are excerpts of the real wikitext served by
// de.wiktionary.org for `Haus` and `gehen`, kept verbatim — including the
// image parameters interleaved with the grammatical ones, which is the trap
// this parser exists to survive.
enum GermanFlexionParserTests {

    // Real `Haus` page excerpt. Note `Dativ Singular*` and the `Bild N`
    // parameters whose values contain pipes.
    private static let hausWikitext = """
    == Haus ({{Sprache|Deutsch}}) ==
    === {{Wortart|Substantiv|Deutsch}}, {{n}} ===
    {{Deutsch Substantiv Übersicht
    |Genus=n
    |Nominativ Singular=Haus
    |Nominativ Plural=Häuser
    |Genitiv Singular=Hauses
    |Genitiv Plural=Häuser
    |Dativ Singular=Haus
    |Dativ Singular*=Hause
    |Dativ Plural=Häusern
    |Akkusativ Singular=Haus
    |Akkusativ Plural=Häuser
    |Bild 1=Leamouth riverside building 1.jpg|mini|1|ein ''Haus'' im [[modern]]en [[Baustil]]
    |Bild 2=Schiller Weimar.jpg|mini|1, 2|[[w:Schillers Wohnhaus|Schiller-''Haus'']] in [[Weimar]]
    }}
    {{Bedeutungen}}
    :[1] Gebäude
    """

    // Real `gehen` page excerpt, including the `Bild` parameter and the
    // starred imperative variants.
    private static let gehenWikitext = """
    == gehen ({{Sprache|Deutsch}}) ==
    === {{Wortart|Verb|Deutsch}} ===
    {{Deutsch Verb Übersicht
    |Präsens_ich=gehe
    |Präsens_du=gehst
    |Präsens_er, sie, es=geht
    |Präteritum_ich=ging
    |Partizip II=gegangen
    |Konjunktiv II_ich=ginge
    |Imperativ Singular=geh
    |Imperativ Singular*=gehe
    |Imperativ Plural=geht
    |Hilfsverb=sein
    |Bild=Blender3D NormalWalkCycle.gif|mini|1|Animation einer ''gehenden'' Person
    }}
    {{Bedeutungen}}
    :[1] sich fortbewegen
    """

    // MARK: - Parsing

    static func testParsesNounTable() throws {
        guard let table = GermanWiktionaryParser.parseFlexion(wikitext: hausWikitext) else {
            throw TestFailure(description: "the Haus flexion table should parse")
        }
        try expectEqual(table.genus, "n", "Genus should be captured; it separates noun/noun homographs")
        try expectEqual(
            table.forms(labeled: "Nominativ Plural"),
            ["Häuser"],
            "the plural the offline lemmatizer cannot derive should come from the table"
        )
        try expectEqual(
            table.forms(labeled: "Dativ Plural"),
            ["Häusern"],
            "every declined plural should be captured"
        )
    }

    static func testDropsImageParameters() throws {
        guard let table = GermanWiktionaryParser.parseFlexion(wikitext: hausWikitext) else {
            throw TestFailure(description: "the Haus flexion table should parse")
        }
        try expect(
            !table.forms.contains { $0.label.hasPrefix("Bild") },
            "image parameters must never be read as grammatical forms"
        )
        try expect(
            !table.forms.contains { $0.surface.contains(".jpg") },
            "a filename must never surface as an inflected form"
        )
        try expect(
            !table.forms.contains { $0.surface.contains("mini") },
            "image caption fragments must not leak into forms"
        )
    }

    static func testCapturesStarredVariants() throws {
        guard let table = GermanWiktionaryParser.parseFlexion(wikitext: hausWikitext) else {
            throw TestFailure(description: "the Haus flexion table should parse")
        }
        let dativeSingulars = table.forms.filter { $0.label == "Dativ Singular" }
        try expectEqual(
            dativeSingulars.map(\.surface),
            ["Haus", "Hause"],
            "a starred parameter should be kept as an additional form of the same label"
        )
        try expectEqual(
            dativeSingulars.map(\.isVariant),
            [false, true],
            "the starred form should be marked as a variant, not as the primary"
        )
    }

    static func testParsesVerbTable() throws {
        guard let table = GermanWiktionaryParser.parseFlexion(wikitext: gehenWikitext) else {
            throw TestFailure(description: "the gehen flexion table should parse")
        }
        try expectEqual(table.auxiliary, "sein", "the auxiliary should be captured")
        try expectEqual(table.forms(labeled: "Partizip II"), ["gegangen"], "Partizip II should be captured")
        try expectEqual(table.forms(labeled: "Präteritum_ich"), ["ging"], "Präteritum should be captured")
        try expect(
            !table.forms.contains { $0.surface.contains(".gif") },
            "the verb table's image parameter must be dropped too"
        )
    }

    static func testReturnsNilWithoutATable() throws {
        try expectEqual(
            GermanWiktionaryParser.parseFlexion(wikitext: "== Haus ==\nno template here"),
            nil,
            "a page with no Übersicht template yields no table"
        )
    }

    // MARK: - Label resolution

    static func testResolvesLabelsTheOfflineRulesCannot() throws {
        guard let haus = GermanWiktionaryParser.parseFlexion(wikitext: hausWikitext),
              let gehen = GermanWiktionaryParser.parseFlexion(wikitext: gehenWikitext) else {
            throw TestFailure(description: "fixtures should parse")
        }

        // The pinned known gap: 'Häuser' never reduces to 'Haus' offline.
        try expectEqual(
            GermanFormLabeler.label(surfaceForm: "Häuser", using: haus),
            .plural,
            "the table should label the plural the offline rule cannot derive"
        )
        // Präsens and Präteritum are indistinguishable offline; the table splits them.
        try expectEqual(
            GermanFormLabeler.label(surfaceForm: "ging", using: gehen),
            .praeteritum,
            "the table should resolve Präteritum, which the offline rule reports as finiteVerb"
        )
        try expectEqual(
            GermanFormLabeler.label(surfaceForm: "gehst", using: gehen),
            .praesens,
            "the table should resolve Präsens"
        )
        try expectEqual(
            GermanFormLabeler.label(surfaceForm: "gegangen", using: gehen),
            .partizipII,
            "the table should agree with the offline rule on Partizip II"
        )
    }

    static func testAmbiguousParameterMatchesUsePriority() throws {
        guard let gehen = GermanFlexionParserTests.parsedGehen() else {
            throw TestFailure(description: "fixture should parse")
        }
        // 'gehe' is both Präsens_ich and Imperativ Singular*; 'geht' is both
        // Präsens_er,sie,es and Imperativ Plural. Priority must make these
        // deterministic rather than dependent on table order.
        try expectEqual(
            GermanFormLabeler.label(surfaceForm: "gehe", using: gehen),
            .praesens,
            "a form matching several parameters should resolve by priority"
        )
        try expectEqual(
            GermanFormLabeler.label(surfaceForm: "geht", using: gehen),
            .praesens,
            "Präsens should win over Imperativ for an ambiguous form"
        )
    }

    static func testUnknownAndCaseInsensitiveLookups() throws {
        guard let haus = GermanWiktionaryParser.parseFlexion(wikitext: hausWikitext) else {
            throw TestFailure(description: "fixture should parse")
        }
        try expectEqual(
            GermanFormLabeler.label(surfaceForm: "häuser", using: haus),
            .plural,
            "lookups should be case-insensitive, matching how words appear mid-sentence"
        )
        try expectEqual(
            GermanFormLabeler.label(surfaceForm: "Hunde", using: haus),
            nil,
            "a form absent from the table yields no label"
        )
        try expectEqual(
            GermanFormLabeler.label(surfaceForm: "Hauses", using: haus),
            nil,
            "a genitive singular has no label to report and must not be called a plural"
        )
    }

    private static func parsedGehen() -> GermanWiktionaryParser.FlexionTable? {
        GermanWiktionaryParser.parseFlexion(wikitext: gehenWikitext)
    }
}
