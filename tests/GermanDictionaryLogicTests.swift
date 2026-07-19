import Foundation

enum GermanDictionaryLogicTests {
    static func testInflectedFormAndDefinitionParsing() throws {
        let inflected = """
        == Bewerbungsunterlagen ({{Sprache|Deutsch}}) ==
        === {{Wortart|Deklinierte Form|Deutsch}} ===
        {{Grammatische Merkmale}}
        *Nominativ Plural des Substantivs '''[[Bewerbungsunterlage]]'''
        {{Grundformverweis Dekl|Bewerbungsunterlage}}
        """
        let inflectedPage = GermanWiktionaryParser.parse(wikitext: inflected)
        try expectEqual(inflectedPage?.lemma, "Bewerbungsunterlage", "German dictionary should resolve an inflected plural to its lemma")
        try expectEqual(inflectedPage?.meanings, [], "inflected-form pages may delegate meanings to the lemma")

        let lemma = """
        == Bewerbungsunterlage ({{Sprache|Deutsch}}) ==
        === {{Wortart|Substantiv|Deutsch}}, {{f}} ===
        {{Bedeutungen}}
        :[1] ''meist im Plural:'' [[Dokument]]e, Papiere zur [[Anbahnung]] einer [[Geschäftsbeziehung]]
        {{Herkunft}}
        :Kompositum
        """
        guard let lemmaPage = GermanWiktionaryParser.parse(wikitext: lemma) else {
            throw TestFailure(description: "German lemma page should parse")
        }
        try expectEqual(lemmaPage.partOfSpeech, "Substantiv", "German dictionary should retain the part of speech")
        try expectEqual(
            lemmaPage.meanings,
            ["meist im Plural: Dokumente, Papiere zur Anbahnung einer Geschäftsbeziehung"],
            "German dictionary should turn Wiktionary links and emphasis into readable text"
        )

        let entry = GermanDictionaryEntry(
            requestedWord: "Bewerbungsunterlagen",
            lemma: "Bewerbungsunterlage",
            partOfSpeech: lemmaPage.partOfSpeech,
            meanings: lemmaPage.meanings
        )
        try expect(entry.markdown.contains("Grundform"), "German dictionary answer should explain lemma resolution")
        try expect(entry.markdown.contains("Deutsch Wiktionary"), "German dictionary answer should include source attribution")
    }
}
