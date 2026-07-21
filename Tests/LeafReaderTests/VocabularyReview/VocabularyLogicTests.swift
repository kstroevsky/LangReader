import Foundation
import NaturalLanguage

private struct StoredWordRecord: Equatable {
    let id: String
    var answer: String
    var srsReviewCount: Int
}

private struct InMemoryWordRecordStore {
    var sqliteRecords: [String: StoredWordRecord] = [:]
    var legacyRecords: [StoredWordRecord] = []
    var didMigrate = false

    mutating func load() -> [StoredWordRecord] {
        if !sqliteRecords.isEmpty {
            return sqliteRecords.values.sorted { $0.id < $1.id }
        }
        if didMigrate {
            return []
        }
        if !legacyRecords.isEmpty {
            for record in legacyRecords {
                sqliteRecords[record.id] = record
            }
            didMigrate = true
            return legacyRecords
        }
        return []
    }

    mutating func save(_ records: [StoredWordRecord]) {
        sqliteRecords = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        didMigrate = true
    }

    mutating func upsert(_ record: StoredWordRecord) {
        sqliteRecords[record.id] = record
        didMigrate = true
    }

    mutating func delete(ids: [String]) {
        for id in ids {
            sqliteRecords.removeValue(forKey: id)
        }
        didMigrate = true
    }
}

enum VocabularyLogicTests {
    static func testVocabularySRS() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let initial = VocabularySRSState.initial(createdAt: date)

        let failed = initial.reviewed(grade: 1, at: date)
        try expectEqual(failed.intervalDays, 0, "failed review should stay same-day")
        try expectEqual(failed.repetition, 0, "failed review resets repetition")
        try expectEqual(failed.lapseCount, 1, "failed review increments lapse count")
        try expect(failed.dueDate > date, "failed review schedules short retry")

        let remembered = initial.reviewed(grade: 3, at: date)
        try expectEqual(remembered.intervalDays, 1, "first remembered review schedules one day")
        try expectEqual(remembered.repetition, 1, "remembered review increments repetition")
        try expectEqual(remembered.activeRecallStreak, 1, "remembered review increments recall streak")
    }

    static func testVocabularyAnswerlessListMode() throws {
        let session = VocabularyReviewSession()
        session.resetForListMode(filter: .all)
        try expect(session.listModeEnabled, "answerless vocabulary should open directly in list mode")
        try expectEqual(session.filter, .all, "answerless vocabulary should show every saved word")
        session.resetForReviewMode()
        try expect(!session.listModeEnabled, "review mode should remain available for answered words")
    }

    static func testWordRecordIncrementalStore() throws {
        var store = InMemoryWordRecordStore()
        store.upsert(StoredWordRecord(id: "a", answer: "old", srsReviewCount: 0))
        try expectEqual(store.load(), [StoredWordRecord(id: "a", answer: "old", srsReviewCount: 0)], "upsert should insert a record")

        store.upsert(StoredWordRecord(id: "a", answer: "new", srsReviewCount: 2))
        try expectEqual(store.load(), [StoredWordRecord(id: "a", answer: "new", srsReviewCount: 2)], "upsert should update answer and SRS")

        store.upsert(StoredWordRecord(id: "b", answer: "second", srsReviewCount: 0))
        store.delete(ids: ["a"])
        try expectEqual(store.load(), [StoredWordRecord(id: "b", answer: "second", srsReviewCount: 0)], "delete(ids:) should remove only requested records")

        store.save([])
        try expectEqual(store.load(), [], "bulk clear should leave store empty")
    }

    static func testWordRecordLegacyMigrationDoesNotReviveClearedData() throws {
        var store = InMemoryWordRecordStore(legacyRecords: [StoredWordRecord(id: "legacy", answer: "old", srsReviewCount: 0)])
        try expectEqual(store.load(), [StoredWordRecord(id: "legacy", answer: "old", srsReviewCount: 0)], "first load should migrate legacy records")
        store.save([])
        try expectEqual(store.load(), [], "cleared migrated store should not reload legacy records")
    }

    static func testVocabularyTextPolicy() throws {
        try expect(VocabularyTextPolicy.isSingleEnglishWord("high-pitched"), "hyphenated words should count as one vocabulary word")
        try expect(VocabularyTextPolicy.isSingleEnglishWord("reader’s"), "curly apostrophes should be accepted in vocabulary words")
        try expect(VocabularyTextPolicy.isSingleEnglishWord("übersende"), "German umlauts should be accepted in vocabulary words")
        try expect(VocabularyTextPolicy.isSingleEnglishWord("Straße"), "German sharp s should be accepted in vocabulary words")
        try expect(VocabularyTextPolicy.isVocabularySelection("persönliches Gespräch"), "short German phrases should be vocabulary selections")
        try expect(!VocabularyTextPolicy.isSingleEnglishWord("Nine-"), "trailing hyphen should not be saved as a complete word")
        try expectEqual(VocabularyTextPolicy.speakableWord("Nine-\ntenths"), "Nine-tenths", "PDF line-broken hyphenated words should be saved as one word")
        try expectEqual(VocabularyTextPolicy.normalizedPDFVocabularyText("con-\ntemptuous"), "contemptuous", "PDF line-broken plain words should drop the layout hyphen")
        try expectEqual(VocabularyTextPolicy.normalizedPDFVocabularyText("si-\ncherzustellen"), "sicherzustellen", "short-prefix German line wraps should restore the whole word")
        try expectEqual(
            VocabularyTextPolicy.normalizedPDFVocabularyText(
                "Ausbildungs-\nkonzept",
                isKnownHyphenatedWord: { _ in false },
                isKnownWord: { $0 == "Ausbildungskonzept" }
            ),
            "Ausbildungskonzept",
            "PDF layout hyphens should be removed when the hyphenated spelling is not a real word"
        )
        try expectEqual(
            VocabularyTextPolicy.normalizedPDFVocabularyText(
                "E-\nMail",
                isKnownHyphenatedWord: { $0 == "E-Mail" }
            ),
            "E-Mail",
            "genuine hyphenated words should retain their hyphen across a PDF line break"
        )
        try expectEqual(
            VocabularyTextPolicy.normalizedPDFVocabularyText(
                "Schadenser-satzforderung",
                lineBrokenHyphenRange: NSRange(location: 10, length: 1),
                isKnownHyphenatedWord: { _ in false },
                isKnownWord: { $0 == "Schadensersatzforderung" }
            ),
            "Schadensersatzforderung",
            "a visually wrapped word should drop its layout hyphen even when PDFKit omits the newline"
        )
        try expectEqual(
            VocabularyTextPolicy.dehyphenatedPDFLayoutCandidate(
                word: "Schadenser-satzforderung",
                context: "Von einer Schadenser- satzforderung sehen wir vorerst ab."
            ),
            "Schadensersatzforderung",
            "stored context should identify a legacy layout hyphen for repair"
        )
        try expect(
            VocabularyTextPolicy.dehyphenatedPDFLayoutCandidate(
                word: "E-Mail",
                context: "Bitte senden Sie eine E-Mail."
            ) == nil,
            "an inline genuine hyphen should not be marked as a legacy layout break"
        )
        try expectEqual(
            VocabularyTextPolicy.normalizedPDFContextText(
                "Eine feh- lerhafte E- Mail wäre problematisch.",
                isKnownHyphenatedWord: { $0 == "E-Mail" },
                isKnownWord: { $0 == "fehlerhafte" }
            ),
            "Eine fehlerhafte E-Mail wäre problematisch.",
            "occurrence contexts should remove layout hyphens while retaining genuine hyphens"
        )
        try expectEqual(
            VocabularyTextPolicy.normalizedPDFContextText(
                "Hinweis— bitte erneut prüfen.",
                isKnownWord: { _ in false }
            ),
            "Hinweis— bitte erneut prüfen.",
            "occurrence context cleanup should not rewrite punctuation dashes"
        )
        try expectEqual(VocabularyTextPolicy.normalizedPDFVocabularyText("Nine-\ntenths"), "Nine-tenths", "PDF line-broken true hyphenated words should keep the hyphen")
        try expectEqual(
            VocabularyTextPolicy.normalizedPDFVocabularyText(
                "fam-\niliar",
                isKnownWord: { $0 == "familiar" }
            ),
            "familiar",
            "dictionary-backed PDF normalization should prefer known dehyphenated words"
        )
        guard let dehyphenatedPattern = VocabularyTextPolicy.lineBrokenDehyphenatedSearchPattern(for: "wavered") else {
            throw TestFailure(description: "dehyphenated PDF search pattern should be built")
        }
        let dehyphenatedRegex = try NSRegularExpression(pattern: dehyphenatedPattern)
        let splitWordSample = "The cat wa-\nvered across the moonlight."
        try expectEqual(
            dehyphenatedRegex.matches(in: splitWordSample, range: NSRange(location: 0, length: (splitWordSample as NSString).length)).count,
            1,
            "dehyphenated PDF search should match layout-split words"
        )
        let splitSuffixSample = "Damit die Nutzung sichergestellt ist, muss sie si-\ncherzustellen sein."
        let splitSuffixRegex = try NSRegularExpression(
            pattern: #"(?i)"# + VocabularyTextPolicy.lineBrokenHyphenWordPattern(suffix: "cherzustellen")
        )
        try expectEqual(
            splitSuffixRegex.matches(
                in: splitSuffixSample,
                range: NSRange(location: 0, length: (splitSuffixSample as NSString).length)
            ).count,
            1,
            "a selection from the second line of a PDF-wrapped word should find its complete word"
        )
        try expect(!VocabularyTextPolicy.isSingleEnglishWord("two words"), "phrases should not count as a single word")
        try expectEqual(VocabularyTextPolicy.speakableWord(" high-pitched "), "high-pitched", "speakable words should be trimmed")

        try expect(VocabularyTextPolicy.isVocabularySelection("high-pitched voice"), "short English phrases should be vocabulary selections")
        try expect(!VocabularyTextPolicy.isVocabularySelection("one two three four five six"), "long phrases should not be vocabulary selections")
        try expect(!VocabularyTextPolicy.isVocabularySelection("high-pitched voice."), "punctuated sentences should not be saved as vocabulary items")

        guard let searchPattern = VocabularyTextPolicy.boundedSearchPattern(for: "high-pitched") else {
            throw TestFailure(description: "bounded search pattern should be built")
        }
        let searchRegex = try NSRegularExpression(pattern: searchPattern)
        let sample = "A high-pitched voice, not higher-pitched or low-pitched."
        let sampleRange = NSRange(location: 0, length: (sample as NSString).length)
        try expectEqual(searchRegex.matches(in: sample, range: sampleRange).count, 1, "bounded search should match the exact hyphenated word only")

        try expectEqual(
            VocabularyTextPolicy.pdfSearchQueries(for: "Nine-\ntenths"),
            ["Nine-\ntenths", "Nine- tenths", "Nine-tenths"],
            "PDF search should include line-broken hyphen variants"
        )
        try expectEqual(
            VocabularyTextPolicy.pdfSearchQueries(for: "Nine-tenths"),
            ["Nine-tenths", "Nine-\ntenths", "Nine- tenths"],
            "normalized hyphenated words should still search PDF line-break variants"
        )
        try expect(
            VocabularyTextPolicy.pdfSearchQueries(for: "Nine-\ntenths").contains("Nine-tenths"),
            "PDF search should match hyphenated words when PDFKit inserts a line break"
        )

        let emphasisPattern = VocabularyTextPolicy.emphasisPattern(for: "high-pitched")
        let emphasisRegex = try NSRegularExpression(pattern: emphasisPattern, options: [.caseInsensitive])
        try expectEqual(emphasisRegex.matches(in: sample, range: sampleRange).count, 1, "emphasis should use the same word boundary rule")

        try expectEqual(
            VocabularyTextPolicy.canonicalVocabularyKey("ÜBERSENDE"),
            VocabularyTextPolicy.canonicalVocabularyKey("übersende"),
            "vocabulary comparison should ignore German case"
        )
        try expect(
            VocabularyTextPolicy.canonicalVocabularyKey("ubersende") != VocabularyTextPolicy.canonicalVocabularyKey("übersende"),
            "vocabulary comparison should preserve diacritics"
        )

        let germanSample = "Übersende übersende ubersende übersenden. STRASSE Straße STRAẞE."
        let germanMatches = VocabularyOccurrenceMatcher.matches(query: "übersende", in: germanSample)
        try expectEqual(germanMatches.map(\.matchedText), ["Übersende", "übersende"], "occurrence matching should be case-insensitive but diacritic- and boundary-sensitive")
        let sharpSMatches = VocabularyOccurrenceMatcher.matches(query: "Straße", in: germanSample)
        try expectEqual(sharpSMatches.map(\.matchedText), ["Straße", "STRAẞE"], "occurrence matching should distinguish sharp s from ss while accepting capital sharp s")

        let layoutSplit = "Das Ausbildungs-\nkonzept ist gut; ein Ausbildungskonzept bleibt."
        try expectEqual(
            VocabularyOccurrenceMatcher.matches(query: "Ausbildungskonzept", in: layoutSplit).count,
            2,
            "occurrence matching should treat PDF line-wrap hyphens as layout artifacts"
        )
        let genuineHyphen = "Die E-Mail und die E-\nMail sind gleich, Email aber nicht."
        try expectEqual(
            VocabularyOccurrenceMatcher.matches(query: "E-Mail", in: genuineHyphen).count,
            2,
            "occurrence matching should preserve genuine hyphens across PDF line wraps"
        )
    }

    /// The multi-page scan runs in parallel, reuses taggers across pages and
    /// memoizes the fallback lemma lookup. None of that may change what it
    /// finds, so the batch result must equal scanning each page on its own —
    /// same occurrences, same ranges, same matched text, same order.
    static func testGermanLemmaBatchMatchesSequential() throws {
        let pages = [
            "Er ist gestern nach Hause gegangen und hat nichts gesagt.",
            "Die Häuser in der Stadt sind alt. Wir gehen dorthin.",
            "",
            "Sie ging langsam nach Hause. Das Gehen fiel ihr schwer.",
            "Ein ganz anderer Satz ohne das gesuchte Wort.",
            "Am Ende ging es doch, und alle sind zufrieden gegan-\ngen."
        ]

        for (lemma, selected) in [("gehen", "gegangen"), ("Haus", "Häuser"), ("gehen", "ging")] {
            let sequential = pages.map {
                GermanLemmaOccurrenceMatcher.matches(lemma: lemma, selectedForm: selected, in: $0, language: .german)
            }
            let batch = GermanLemmaOccurrenceMatcher.matches(
                lemma: lemma,
                selectedForm: selected,
                inTexts: pages,
                language: .german
            )
            try expectEqual(
                batch.count,
                pages.count,
                "the batch scan should return one result per page for '\(selected)'"
            )
            try expectEqual(
                batch,
                sequential,
                "parallel scanning must find exactly what sequential scanning finds for '\(selected)'"
            )
        }

        // Boundary cases around the parallel path.
        try expectEqual(
            GermanLemmaOccurrenceMatcher.matches(lemma: "gehen", selectedForm: "gegangen", inTexts: [], language: .german),
            [],
            "an empty page list yields no results"
        )
        let single = GermanLemmaOccurrenceMatcher.matches(
            lemma: "gehen",
            selectedForm: "gegangen",
            inTexts: [pages[0]],
            language: .german
        )
        try expectEqual(
            single,
            [GermanLemmaOccurrenceMatcher.matches(lemma: "gehen", selectedForm: "gegangen", in: pages[0], language: .german)],
            "the single-page path should agree with the per-page scanner"
        )
        try expectEqual(
            GermanLemmaOccurrenceMatcher.matches(lemma: "gehen", selectedForm: "gegangen", inTexts: ["", "", ""], language: .german),
            [[], [], []],
            "empty pages should produce empty results rather than being skipped"
        )
    }

    /// The reusable-tagger overload must return exactly what the allocating one
    /// does, including when the same tagger is reused across many words.
    static func testGermanLemmaResolverTaggerReuse() throws {
        let words = ["gegangen", "ging", "Häuser", "Bücher", "sprach", "gegangen", "ging"]
        let tagger = NLTagger(tagSchemes: [.lemma])
        for word in words {
            try expectEqual(
                GermanLemmaResolver.lemma(for: word, tagger: tagger, language: .german),
                GermanLemmaResolver.lemma(for: word, language: .german),
                "reusing a tagger must not change the lemma resolved for '\(word)'"
            )
        }
    }

    static func testGermanLemmaGrouping() throws {
        try expectEqual(GermanLemmaResolver.lemma(for: "fehlerhafte", language: .german), "fehlerhaft", "German adjective inflection should resolve to its lemma")
        try expectEqual(GermanLemmaResolver.lemma(for: "fehlerhaften", language: .german), "fehlerhaft", "related German adjective forms should share one lemma")
        try expectEqual(
            GermanLemmaResolver.groupingKey(word: "Fehlerhaften", language: .german),
            GermanLemmaResolver.groupingKey(word: "fehlerhafte", language: .german),
            "German inflected forms should share a case-insensitive grouping key"
        )

        let text = "Eine fehlerhafte Rechnung entstand wegen eines fehlerhaften Eintrags. Ein fehlerhaf-\nten Eintrag. Ein Fehler blieb."
        let matches = GermanLemmaOccurrenceMatcher.matches(
            lemma: "fehlerhaft",
            selectedForm: "fehlerhafte",
            in: text,
            language: .german
        )
        try expectEqual(
            matches.map(\.matchedText),
            ["fehlerhafte", "fehlerhaften", "fehlerhaf-\nten"],
            "lemma scanning should find different inflected forms without matching unrelated nouns"
        )
        let batchMatches = GermanLemmaOccurrenceMatcher.matches(
            lemmasByKey: ["fehlerhaft": "fehlerhaft"],
            in: text,
            language: .german
        )
        try expectEqual(batchMatches["fehlerhaft"]?.map(\.matchedText), matches.map(\.matchedText), "batch rescans should preserve all exact and line-wrapped inflected occurrences")
        try expect(batchMatches["fehler"] == nil, "batch rescans should not create an unrelated noun group")

    }

    /// A word split across a line as "Er-\nfolg" tokenizes into a stray "folg",
    /// whose lemma is "folgen". Matching that fragment turned the unrelated noun
    /// "Erfolg" into a false occurrence of the verb "folgen" — a phantom the user
    /// could not find highlighted in the document. The joined form is "Erfolg"
    /// (lemma "Erfolg"), so the line-break must contribute no match at all, while
    /// genuine standalone forms on the same page still resolve.
    static func testGermanLemmaLineWrapFragmentIsNotAFalseMatch() throws {
        let text = "Für den Er-\nfolg muss das Portal gewählt werden. Wir folgen dem Plan und folgten gestern."

        let matches = GermanLemmaOccurrenceMatcher.matches(
            lemma: "folgen",
            selectedForm: "folgen",
            in: text,
            language: .german
        )
        try expect(
            !matches.contains { VocabularyTextPolicy.canonicalVocabularyKey($0.matchedText) == "folg" },
            "the hyphen-line-break fragment 'folg' of 'Erfolg' must not match the lemma 'folgen'"
        )
        try expectEqual(
            matches.map(\.matchedText),
            ["folgen", "folgten"],
            "real occurrences of 'folgen' should still be matched around the false fragment"
        )

        let batch = GermanLemmaOccurrenceMatcher.matches(lemmasByKey: ["folgen": "folgen"], in: text, language: .german)
        try expectEqual(
            batch["folgen"]?.map(\.matchedText),
            ["folgen", "folgten"],
            "the backfill matcher must agree and must not spawn a 'folg' occurrence"
        )
    }

    /// The occurrence engine is language-neutral: pass a language and it groups
    /// that language's inflected forms. The same forms under a different
    /// language do NOT group, proving the language parameter is load-bearing.
    static func testLemmaEngineIsLanguageParameterized() throws {
        // French — all forms of "parler" collapse to one lemma under .french.
        let fr = "Je parle, tu parles, ils parlent souvent. Nous avons parlé hier."
        let frGroups = GermanLemmaOccurrenceMatcher.matches(lemmasByKey: ["parler": "parler"], in: fr, language: .french)
        try expectEqual(
            Set((frGroups["parler"] ?? []).map { $0.matchedText.lowercased() }),
            ["parle", "parles", "parlent", "parlé"],
            "French inflected forms of 'parler' should group under one lemma"
        )
        // The identical text under German fails to group them — the parameter,
        // not the text, is what makes the grouping work.
        let frUnderGerman = GermanLemmaOccurrenceMatcher.matches(lemmasByKey: ["parler": "parler"], in: fr, language: .german)
        try expect(
            (frUnderGerman["parler"]?.count ?? 0) < (frGroups["parler"]?.count ?? 0),
            "German lemmatization must not reproduce the French grouping"
        )

        // Spanish.
        let es = "Yo hablo, tú hablas y ellos hablan mucho."
        let esGroups = GermanLemmaOccurrenceMatcher.matches(lemmasByKey: ["hablar": "hablar"], in: es, language: .spanish)
        try expectEqual(
            Set((esGroups["hablar"] ?? []).map { $0.matchedText.lowercased() }),
            ["hablo", "hablas", "hablan"],
            "Spanish inflected forms of 'hablar' should group under one lemma"
        )

        // English, via the resolver directly.
        try expectEqual(GermanLemmaResolver.lemma(for: "running", language: .english), "run", "English -ing form should lemmatize under .english")
        try expectEqual(GermanLemmaResolver.lemma(for: "children", language: .english), "child", "English irregular plural should lemmatize under .english")

        // Russian groups well too, and is why the supported set includes it.
        try expectEqual(GermanLemmaResolver.lemma(for: "части", language: .russian), "часть", "Russian inflected noun should lemmatize under .russian")

        // The detector picks the document language and gates on support.
        try expectEqual(
            VocabularyLanguageDetector.language(forSample: "Je parle français et je lis un long texte en français ici."),
            .french,
            "the detector should recognize a French sample"
        )
        try expectEqual(
            VocabularyLanguageDetector.language(forSample: "kort"),
            VocabularyLanguageDetector.fallback,
            "too-short samples fall back rather than guessing"
        )
    }

    /// English gets the same grammatical labeling German has, built on the same
    /// "never guess" rule: only signals measured to be reliable are claimed.
    static func testEnglishFormLabeling() throws {
        func label(_ surface: String, _ lemma: String, _ context: String) -> WordFormLabel? {
            EnglishFormLabeler.label(surfaceForm: surface, lemma: lemma, context: context)
        }

        // Verbs — each label rests on a proven signal.
        try expectEqual(label("walk", "walk", "I walk to work every day and enjoy the long morning air."), .grundform, "surface equal to the lemma is the base form")
        try expectEqual(label("running", "run", "They are running fast across the wide green field today."), .presentParticiple, "the -ing form is proven morphologically")
        try expectEqual(label("walks", "walk", "He walks to work each morning before the sun comes up."), .thirdPersonSingular, "lemma+s on a verb is the third person singular")
        try expectEqual(label("walked", "walk", "She has walked home already, so the room is now empty."), .pastParticiple, "an auxiliary in the clause proves the past participle")
        // Morphology outranks the auxiliary rule: a lemma+s form cannot be a
        // participle, however a copular "is"/"was" sits earlier in the clause.
        try expectEqual(
            label("looks", "look", "The reason she looks away is that the light is far too bright."),
            .thirdPersonSingular,
            "a lemma+s verb stays third person singular despite a copula in the clause"
        )
        try expectEqual(label("written", "write", "I have written the letter and posted it this morning."), .pastParticiple, "irregular participles are proven by the auxiliary too")

        // Nouns — English has no case system, so a differing surface is a plural.
        try expectEqual(label("children", "child", "The children played outside for hours in the summer sun."), .plural, "irregular plurals are labeled")
        try expectEqual(label("books", "book", "She read three books during the long quiet weekend at home."), .plural, "regular plurals are labeled")
        try expectEqual(label("book", "book", "She read a book during the long quiet weekend at home."), .grundform, "a singular noun is the base form")

        // Never guess: an attributive participle is indistinguishable from a
        // past tense here ("the completed work"), so neither is claimed.
        try expectEqual(
            label("completed", "complete", "The completed work impressed everyone who saw it that day."),
            .finiteVerb,
            "an ambiguous past form takes the honest coarse label, never a guessed tense"
        )
        try expectEqual(
            label("walked", "walk", "She walked home yesterday evening after the meeting ended."),
            .finiteVerb,
            "a past form with no auxiliary is reported as a conjugated form"
        )

        // Comparatives are tagged Adverb by the tagger, exactly as in German, so
        // no adjective-specific label is trustworthy.
        try expect(
            label("bigger", "big", "This is a bigger house than the one they lived in before.") == nil,
            "comparatives stay unlabeled rather than mislabeled"
        )

        // A document in another language must never get English labels.
        try expect(
            label("gegangen", "gehen", "Er ist gestern nach Hause gegangen und hat nichts gesagt.") == nil,
            "German text must not receive English grammatical labels"
        )
    }

    /// Labeling routes by language, and languages without a labeler produce no
    /// labels rather than borrowing another language's grammar.
    static func testFormLabelingRoutesByLanguage() throws {
        let englishContext = "She has walked home already, so the room is now empty."
        try expectEqual(
            VocabularyFormLabeling.label(surfaceForm: "walked", lemma: "walk", context: englishContext, language: .english),
            .pastParticiple,
            "English routes to the English labeler"
        )
        let germanContext = "Er ist gestern nach Hause gegangen und hat nichts gesagt."
        try expectEqual(
            VocabularyFormLabeling.label(surfaceForm: "gegangen", lemma: "gehen", context: germanContext, language: .german),
            .partizipII,
            "German still routes to the German labeler"
        )
        try expect(
            VocabularyFormLabeling.label(surfaceForm: "parle", lemma: "parler", context: "Je parle français.", language: .french) == nil,
            "a language with no labeler yields no label rather than a borrowed one"
        )
        try expect(VocabularyFormLabeling.hasLabeler(for: .english) && VocabularyFormLabeling.hasLabeler(for: .german), "English and German both have labelers")
        try expect(!VocabularyFormLabeling.hasLabeler(for: .french), "French has no labeler yet")

        // The label cache has no language column, so the version namespaces it.
        // Without this the same spelling in two languages would collide.
        try expect(
            VocabularyFormLabeling.cacheVersion(for: .english) != VocabularyFormLabeling.cacheVersion(for: .german),
            "each language's cached labels must live in their own version namespace"
        )
    }

    /// Detection must sample running prose from across the document, not the
    /// first pages. Front matter is titles, author lists and (in scanned books)
    /// OCR noise: sampling it detected a real English art book as Turkish, which
    /// then fell back to German. Prose-dense pages give the right answer.
    static func testLanguageDetectionSamplesProseNotFrontMatter() throws {
        let frontMatter = """
        ISM “and Surreall Artists en VVeven PRNP 1DU} nn f Ti rrress Tl dea
        Angels of Anarchy Edited by Patricia Allmer Roger Cardinal Mary Ann Caws
        Manchester PRESM@EL Munich : Berlin - London: New York 2009 p. 255-56
        """
        let prose = """
        Marie Parent was born the eighth of nine children of the architect Lucien Parent.
        She studied art at the school of fine arts and at the studio of a non-conformist
        artist in Montreal, and her first solo exhibition was held in the city some years
        later. The work that she showed there was received with considerable interest by
        the critics who wrote about it, and she continued to paint for many more decades.
        """
        // 12 pages: front matter first, prose in the body — the shape that broke.
        let pages = [frontMatter, frontMatter, frontMatter] + Array(repeating: prose, count: 9)
        try expectEqual(
            VocabularyLanguageDetector.language(pageCount: pages.count, pageText: { pages[$0] }),
            .english,
            "detection should follow the body prose, not the front matter"
        )

        // Prose scoring must prefer real sentences over layout/OCR noise.
        try expect(
            VocabularyLanguageDetector.proseScore(prose) > VocabularyLanguageDetector.proseScore(frontMatter),
            "running prose should outscore front matter"
        )
        try expectEqual(
            VocabularyLanguageDetector.proseScore("1A - 5. 1B - 5. 1C - 2. 2 - 8. 3 - 10. 44 / 207"),
            0,
            "a page of numbers and layout noise should score as non-prose"
        )

        // Sampling skips front matter but never runs off the end.
        let indices = VocabularyLanguageDetector.sampleIndices(pageCount: 264)
        try expect(indices.first ?? 0 > 0, "sampling should skip the opening front matter")
        try expect(indices.allSatisfy { $0 < 264 }, "sampled indices must stay in range")
        try expect(indices.count <= VocabularyLanguageDetector.maxSampledPages, "sampling stays bounded for large documents")
        try expectEqual(
            VocabularyLanguageDetector.sampleIndices(pageCount: 3),
            [0, 1, 2],
            "a short document samples every page"
        )
        try expectEqual(VocabularyLanguageDetector.sampleIndices(pageCount: 0), [], "an empty document samples nothing")
    }

    /// The load-time prune that heals libraries saved before the recognizer fix.
    /// A candidate is either a line-break fragment (surface only inside a larger
    /// word) or a case-folded homograph (surface folds to the group key but is
    /// spelled with different case). A candidate is dropped only if the fixed
    /// group scan no longer assigns it to the group, so same-line compound
    /// constituents ("Abteilung" in "IT-Abteilung") and differently-keyed
    /// inflections ("folgende", "folgt") are always kept.
    static func testMisfiledOccurrenceDetection() throws {
        // Line-break fragment candidates: surface only ever inside a larger word.
        for (surface, context) in [
            ("folg", "Für den Erfolg muss das richtige Portal gewählt werden."),
            ("kommt", "Worauf es noch ankommt, erfährst du in den Tipps."),
            ("Abteilung", "Und ihr von der IT-Abteilung organisiert das doch, oder?")
        ] {
            try expect(
                VocabularyTextPolicy.surfaceOccursOnlyWithinLargerWord(surface: surface, context: context),
                "'\(surface)' only appears inside a larger word in its context ⇒ candidate"
            )
        }
        for (surface, context) in [
            ("folgt", "Zuerst kommt der Antrag, dann folgt der Bescheid."),
            ("Portal", "Man muss das richtige Portal wählen, sonst klappt es nicht."),
            ("folg", ""),
            ("folg", "Ein Satz ganz ohne das Wort.")
        ] {
            try expect(
                !VocabularyTextPolicy.surfaceOccursOnlyWithinLargerWord(surface: surface, context: context),
                "'\(surface)' is a whole word / empty / absent and is not a line-break candidate"
            )
        }

        // Case-folded homograph: same key as the group lemma, different case.
        try expect(
            VocabularyTextPolicy.canonicalVocabularyKey("Folgen") == VocabularyTextPolicy.canonicalVocabularyKey("folgen")
                && !VocabularyTextPolicy.surfaceMatchesLemmaExactly("Folgen", "folgen"),
            "the noun 'Folgen' folds to the verb group key 'folgen' but differs by case ⇒ candidate"
        )
        try expect(
            VocabularyTextPolicy.surfaceMatchesLemmaExactly("folgen", "folgen"),
            "the verb base 'folgen' matches the group lemma exactly ⇒ not a candidate"
        )

        // Group re-scan decides candidates.
        try expect(
            !GermanLemmaOccurrenceMatcher.groupReproducesOccurrence(
                surfaceForm: "folg", groupLemma: "folgen",
                in: "Für den Erfolg muss das richtige Portal gewählt werden.",
                language: .german
            ),
            "'folg' from 'Erfolg' is no longer assigned to group 'folgen' ⇒ prune"
        )
        try expect(
            !GermanLemmaOccurrenceMatcher.groupReproducesOccurrence(
                surfaceForm: "Folgen", groupLemma: "folgen",
                in: "Welche Folgen hätte das?",
                language: .german
            ),
            "the noun 'Folgen' (lemma 'Folge') is no longer assigned to verb group 'folgen' ⇒ prune"
        )
        try expect(
            GermanLemmaOccurrenceMatcher.groupReproducesOccurrence(
                surfaceForm: "Abteilung", groupLemma: "Abteilung",
                in: "Und ihr von der IT-Abteilung organisiert das doch, oder?",
                language: .german
            ),
            "'Abteilung' in 'IT-Abteilung' is still assigned to its group ⇒ keep"
        )
    }

    /// The German noun "Folgen" (lemma "Folge") must never be filed under the
    /// verb group "folgen" via the lemma/surface expansion: their surfaces fold
    /// to one key, so a case-insensitive surface match would merge them.
    /// Capitalization is the noun/verb signal. (The exact-form query path, which
    /// matches whatever spelling the user actually saved, is out of scope here —
    /// the real group is filed under "folgenden", so "Folgen" only ever entered
    /// it through the lemma/surface path exercised below.)
    static func testGermanNounNotGroupedWithVerbHomograph() throws {
        let text = "Wir folgen dem Plan. Welche Folgen hätte das? Der Fehler folgt daraus."

        // Backfill / group-expansion path (no exact-form query).
        let batch = GermanLemmaOccurrenceMatcher.matches(lemmasByKey: ["folgen": "folgen"], in: text, language: .german)
        try expect(
            batch["folgen"]?.contains { $0.matchedText == "Folgen" } != true,
            "the backfill scan must keep the noun 'Folgen' out of the verb group 'folgen'"
        )
        try expect(
            batch["folgen"]?.contains { $0.matchedText == "folgt" } == true,
            "the backfill scan must still find the real verb form 'folgt'"
        )

        // Lemma/surface expansion around a different saved form ("folgt"): the
        // noun "Folgen" must not be swept in, while real verb forms still match.
        let sequential = GermanLemmaOccurrenceMatcher.matches(lemma: "folgen", selectedForm: "folgt", in: text, language: .german)
        try expect(
            !sequential.contains { $0.matchedText == "Folgen" },
            "expanding the verb group must not match the noun 'Folgen'"
        )
        try expect(
            sequential.contains { $0.matchedText == "folgt" } && sequential.contains { $0.matchedText == "folgen" },
            "expanding the verb group must still match 'folgt' and the base 'folgen'"
        )

        // Group membership (used by the load-time prune) excludes the noun.
        try expect(
            !GermanLemmaOccurrenceMatcher.groupReproducesOccurrence(
                surfaceForm: "Folgen", groupLemma: "folgen", in: "Welche Folgen hätte das?",
                language: .german
            ),
            "the noun 'Folgen' is not a member of the verb group 'folgen'"
        )
    }

    static func testPersonalVocabularyTokenizerAndPolicy() throws {
        let counts = PersonalVocabularyTokenizer.lemmaCounts(in: """
        The Reader’s dogs, and high-pitched dogs, Nine-tenths.
        FREE eBOOKS AT PLANET eBOOK.COM
        21
        ashes—a gigantic—their wa-
        vered con-
        temptuous ing
        """)
        try expect(counts["the"] == nil, "tokenizer should skip common function words")
        try expect(counts["and"] == nil, "tokenizer should skip conjunction stop words")
        try expect(counts["free"] == nil, "tokenizer should skip Planet eBook footer lines")
        try expect(counts["planet"] == nil, "tokenizer should skip Project Gutenberg footer text")
        try expect(counts["com"] == nil, "tokenizer should skip URL suffix fragments")
        try expect(counts["ing"] == nil, "tokenizer should skip suffix fragments")
        try expectEqual(counts["reader"], 1, "tokenizer should normalize possessives")
        try expectEqual(counts["dogs"], 2, "tokenizer should aggregate repeated words")
        try expectEqual(counts["high-pitched"], 1, "tokenizer should keep internal hyphenated words")
        try expectEqual(counts["nine-tenths"], 1, "tokenizer should keep fraction-like hyphenated words")
        try expectEqual(counts["ashes"], 1, "tokenizer should not join words across em dashes")
        try expectEqual(counts["gigantic"], 1, "tokenizer should split em dash compounds")
        try expectEqual(counts["wavered"], 1, "tokenizer should join short-prefix PDF layout hyphenation")
        try expectEqual(counts["contemptuous"], 1, "tokenizer should join common PDF layout hyphenation")
        try expect(counts["wa"] == nil, "tokenizer should not keep layout-hyphen prefixes")
        try expect(counts["vered"] == nil, "tokenizer should not keep layout-hyphen suffixes")
        try expect(!PersonalVocabularyTokenizer.isStoredLemmaTrackable("the"), "stored stop words should be treated as cleanup noise")
        try expect(!PersonalVocabularyTokenizer.isStoredLemmaTrackable("ebook"), "stored footer fragments should be treated as cleanup noise")
        try expect(PersonalVocabularyTokenizer.isStoredLemmaTrackable("gravity"), "valid stored lemmas should remain trackable")

        let knownByRepeatedExposure = PersonalVocabularyProfilePolicy.status(
            seenCount: 4,
            unqueriedSeenCount: 4,
            postQueryUnqueriedSeenCount: 0,
            queriedCount: 0,
            reviewCorrectCount: 0,
            reviewWrongCount: 0,
            documentsSeen: 1
        )
        try expectEqual(knownByRepeatedExposure, .known, "repeated unqueried exposure should become known")

        let likelyKnown = PersonalVocabularyProfilePolicy.status(
            seenCount: 3,
            unqueriedSeenCount: 3,
            postQueryUnqueriedSeenCount: 0,
            queriedCount: 0,
            reviewCorrectCount: 0,
            reviewWrongCount: 0,
            documentsSeen: 3
        )
        try expectEqual(likelyKnown, .likelyKnown, "low-count multi-document unqueried exposure should become likely known")

        let learning = PersonalVocabularyProfilePolicy.status(
            seenCount: 30,
            unqueriedSeenCount: 30,
            postQueryUnqueriedSeenCount: 0,
            queriedCount: 1,
            reviewCorrectCount: 0,
            reviewWrongCount: 0,
            documentsSeen: 3
        )
        try expectEqual(learning, .learning, "queried words should be treated as learning")

        let recoveredKnown = PersonalVocabularyProfilePolicy.status(
            seenCount: 34,
            unqueriedSeenCount: 34,
            postQueryUnqueriedSeenCount: 4,
            queriedCount: 1,
            reviewCorrectCount: 0,
            reviewWrongCount: 0,
            documentsSeen: 1
        )
        try expectEqual(recoveredKnown, .known, "queried words should recover to known after repeated unqueried reading")

        let observed = PersonalVocabularyProfilePolicy.status(
            seenCount: 1,
            unqueriedSeenCount: 1,
            postQueryUnqueriedSeenCount: 0,
            queriedCount: 0,
            reviewCorrectCount: 0,
            reviewWrongCount: 0,
            documentsSeen: 1
        )
        try expectEqual(observed, .observed, "low-signal seen words should be observed")

        try expectEqual(PersonalVocabularyExposurePolicy.webProgressBucket(0.123), 24, "web progress bucket should be stable")
        try expectEqual(PersonalVocabularyExposurePolicy.webProgressBucket(2), 200, "web progress bucket should clamp high")
    }

    static func testVocabularyExporter() throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let records = [
            VocabularyExporter.Record(word: "alpha", answer: " first answer ", location: "p. 1", context: "context", source: "Book", createdAt: createdAt),
            VocabularyExporter.Record(word: "Alpha", answer: " first answer ", location: "p. 3", context: "second context", source: "Book", createdAt: createdAt),
            VocabularyExporter.Record(word: "empty", answer: "   ", location: "p. 2", context: "", source: "Book", createdAt: createdAt),
            VocabularyExporter.Record(
                word: "Fehlerhafte",
                lemma: "fehlerhaft",
                surfaceForm: "fehlerhaften",
                answer: "incorrect",
                location: "p. 4",
                context: "wegen eines fehlerhaften Eintrags",
                source: "Buch",
                createdAt: createdAt
            )
        ]
        let exportable = VocabularyExporter.exportableRecords(records)
        try expectEqual(exportable.map(\.word), ["alpha", "Alpha", "empty", "Fehlerhafte"], "answerless and Unicode vocabulary should remain exportable")
        try expectEqual(VocabularyExporter.csvEscaped("a,\"b\""), "\"a,\"\"b\"\"\"", "CSV values should quote and escape quotes")
        try expectEqual(VocabularyExporter.safeFileName("A/B?C:D"), "A-B-C-D", "unsafe filename characters should be replaced")

        let markdown = VocabularyExporter.markdown(
            records: exportable,
            documentTitle: "Book",
            labels: VocabularyExporter.MarkdownLabels(
                titleSuffix: "Vocabulary",
                exportedAt: "Exported at",
                wordCount: "Word count",
                location: "Location",
                context: "Context"
            ),
            exportedAt: createdAt
        ) { record in
            record.answer
        }
        try expect(markdown.contains("# Book Vocabulary"), "markdown should include title")
        try expect(markdown.contains("- Context：context"), "markdown should include non-empty context")
        try expect(markdown.contains("- Location：p. 3"), "markdown should list every occurrence")
        try expectEqual(markdown.components(separatedBy: "## alpha").count - 1, 1, "markdown should group case-insensitive occurrences under one heading")
        try expect(markdown.contains("## Fehlerhafte"), "markdown should preserve the first selected German form as its heading")
        try expect(markdown.contains("**fehlerhaften**"), "markdown should retain the exact inflected form for an occurrence")

        let csv = VocabularyExporter.csv(records: exportable) { record in
            record.answer
        }
        try expect(csv.contains("Word,Page,Context,Source,Created At,Answer"), "CSV should include occurrence-oriented header")
        try expect(csv.contains("\"alpha\",\"p. 1\",\"context\",\"Book\""), "CSV should include escaped occurrence records")
        try expect(csv.contains("\"empty\",\"p. 2\",\"\",\"Book\""), "CSV should include answerless occurrences")
        try expect(csv.contains("\"fehlerhaften\",\"p. 4\""), "CSV should export the exact Unicode surface form for each occurrence")
    }

    static func testVocabularyAnswerFormatter() throws {
        let answer = """
        ## **Induction**

        中文释义：
        • n. 归纳
        """
        try expectEqual(
            VocabularyAnswerFormatter.answerBody(answer, word: "induction"),
            "中文释义：\n• n. 归纳",
            "answer formatter should remove duplicate word heading and blank lines"
        )
        try expectEqual(
            VocabularyAnswerFormatter.normalizedHeading("__Induction ：__"),
            "induction",
            "heading normalization should trim markdown emphasis and punctuation"
        )
    }

    static func testVocabularyReviewCardSelector() throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let first = vocabularyRecord(id: "first", word: "alpha", createdAt: createdAt)
        let second = vocabularyRecord(id: "second", word: "beta", createdAt: createdAt.addingTimeInterval(1))
        let records = [first, second]

        let session = VocabularyReviewSession()
        session.priority = .newWordsFirst
        session.reviewIndex = 8
        guard let initial = VocabularyReviewCardSelector.selection(records: records, session: session) else {
            throw TestFailure(description: "selector should return a review card")
        }
        try expectEqual(initial.record.word, "beta", "new words first should select newest due record")
        try expectEqual(initial.position, 2, "selector should clamp an out-of-range review index to the last visible card")
        try expectEqual(initial.total, 2, "selector should report visible review count")
        try expectEqual(session.reviewIndex, 1, "selector should clamp session review index")

        session.contextShown = true
        session.cardKey = session.key(for: first)
        guard let preserved = VocabularyReviewCardSelector.selection(records: records, session: session) else {
            throw TestFailure(description: "selector should preserve currently shown card")
        }
        try expectEqual(preserved.record.word, "alpha", "visible context card should remain selected")
        try expectEqual(preserved.position, 1, "preserved card should keep its visible queue position")
        try expectEqual(preserved.total, 2, "preserved card should keep total count")
    }

    static func testVocabularyDailyGoalPolicy() throws {
        let now = Date()
        let old = now.addingTimeInterval(-172_800)
        let reviewed = VocabularyExportRecord(
            ids: ["reviewed"],
            word: "reviewed",
            answer: "answer",
            dictionaryTags: nil,
            dictionaryFrequency: nil,
            location: "",
            context: "",
            createdAt: old,
            srs: VocabularySRSState.initial(createdAt: old).reviewed(grade: 3, at: now)
        )
        let pending = vocabularyRecord(id: "pending", word: "pending", createdAt: old)

        try expectEqual(VocabularyDailyGoalPolicy.normalizedGoal(0), 10, "invalid daily goal should use default")
        try expectEqual(
            VocabularyDailyGoalPolicy.reviewedTodayCount(records: [reviewed, pending]),
            1,
            "daily goal should count only records reviewed today"
        )
    }

    static func testVocabularyLearningStats() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let older = calendar.date(byAdding: .day, value: -3, to: now)!

        var reviewedToday = VocabularySRSState.initial(createdAt: older)
        reviewedToday.reviewCount = 3
        reviewedToday.lapseCount = 1
        reviewedToday.lastReviewedAt = now

        var mastered = VocabularySRSState.initial(createdAt: older)
        mastered.reviewCount = 2
        mastered.lastReviewedAt = yesterday
        mastered.activeRecallStreak = 3
        mastered.intervalDays = 7
        mastered.dueDate = Date().addingTimeInterval(86_400)

        let stats = VocabularyLearningStatsCalculator.stats(
            records: [
                vocabularyRecord(id: "today", word: "today", createdAt: older, srs: reviewedToday),
                vocabularyRecord(id: "mastered", word: "mastered", createdAt: older, srs: mastered),
                vocabularyRecord(id: "new", word: "new", createdAt: now)
            ],
            now: now,
            calendar: calendar
        )

        try expectEqual(stats.totalCount, 3, "stats should count all vocabulary records")
        try expectEqual(stats.reviewedTodayCount, 1, "stats should count records reviewed today")
        try expectEqual(stats.masteredCount, 1, "stats should count mastered records")
        try expectEqual(stats.recallRatePercent, 80, "stats should estimate recall rate from review lapses")
        try expectEqual(stats.streakDays, 2, "stats should count consecutive active review days ending today")
    }

    static func testSelectionToolbarConfiguration() throws {
        let offlineState = ReaderCapabilityState(
            isOnline: false,
            hasModelAPIKey: true,
            isLocalDictionaryInstalled: true
        )
        try expectEqual(offlineState.queryCapability, .offlineDictionary, "offline capability should prefer local dictionary mode")

        try expectEqual(
            ReaderQueryCapability.current(isOnline: false, hasModelAPIKey: true),
            .offlineDictionary,
            "offline state should use the local dictionary even when an API key exists"
        )
        try expectEqual(
            ReaderQueryCapability.current(isOnline: true, hasModelAPIKey: false),
            .needsModelConfiguration,
            "online state without an API key should prompt for model configuration"
        )
        try expectEqual(
            ReaderQueryCapability.current(isOnline: true, hasModelAPIKey: true),
            .modelAvailable,
            "online state with an API key should enable model actions"
        )

        let offlineWord = SelectionToolbarConfiguration.make(
            isVocabularySelection: true,
            queryCapability: .offlineDictionary,
            shouldShowSpeakAction: false,
            isPDFSelection: true
        )
        try expectEqual(offlineWord.contextAction, .addWord, "offline word selections should keep the word action")
        try expectEqual(offlineWord.displayMode, .offlineWord, "offline word selections should show only word/speak/copy actions")
        try expect(offlineWord.showsVocabularySaveAction, "PDF vocabulary selections should expose the local save action without a model")
        try expect(!offlineWord.isVocabularySelectionSaved, "a newly selected PDF vocabulary word should show Save")

        let savedWord = SelectionToolbarConfiguration.make(
            isVocabularySelection: true,
            queryCapability: .offlineDictionary,
            shouldShowSpeakAction: false,
            isPDFSelection: true,
            isVocabularySelectionSaved: true
        )
        try expect(savedWord.isVocabularySelectionSaved, "a saved PDF vocabulary word should switch the toolbar to Remove")

        let needsKeyText = SelectionToolbarConfiguration.make(
            isVocabularySelection: false,
            queryCapability: .needsModelConfiguration,
            shouldShowSpeakAction: true
        )
        try expectEqual(needsKeyText.contextAction, .summarize, "non-word selections should keep summarize as their context action")
        try expectEqual(needsKeyText.displayMode, .needsModelKeyCopyOnly, "unconfigured model text selections should show copy plus settings")
        try expect(!needsKeyText.showsVocabularySaveAction, "non-vocabulary selections should not expose a save action")

        let full = SelectionToolbarConfiguration.make(
            isVocabularySelection: true,
            queryCapability: .modelAvailable,
            shouldShowSpeakAction: true
        )
        try expectEqual(full.displayMode, .full(showsSpeak: true), "configured online state should expose the full toolbar")
    }

    static func testLocalDictionaryFallbackRequiresOfflineState() throws {
        let timeout = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        try expect(
            RequestAvailabilityPolicy.shouldUseLocalDictionaryFallback(for: timeout, isOnline: false),
            "offline network errors should use local dictionary fallback"
        )
        try expect(
            !RequestAvailabilityPolicy.shouldUseLocalDictionaryFallback(for: timeout, isOnline: true),
            "online network errors should surface the model error instead of silently using local dictionary"
        )
    }

    static func testVocabularyReviewDisplayRecordLoaderLoadsOnlyCurrentRecord() throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let record = vocabularyRecord(id: "current", word: "induction", createdAt: createdAt)
        var lookedUpWords: [String] = []
        var persisted: [(String, VocabularyExportRecord)] = []

        let displayRecord = VocabularyReviewDisplayRecordLoader.displayRecord(
            for: record,
            metadataLookup: { word in
                lookedUpWords.append(word)
                return (tags: "cet6 gre", frequency: 500)
            },
            persistTags: { tags, record in
                persisted.append((tags, record))
            }
        )

        try expectEqual(lookedUpWords, ["induction"], "display loader should look up only the requested review card")
        try expectEqual(displayRecord.dictionaryTags, "cet6 gre", "display loader should attach dictionary tags to the current card")
        try expectEqual(persisted.map(\.0), ["cet6 gre"], "display loader should persist tags once for the current card")
    }

    private static func vocabularyRecord(
        id: String,
        word: String,
        createdAt: Date,
        srs: VocabularySRSState? = nil
    ) -> VocabularyExportRecord {
        VocabularyExportRecord(
            ids: [id],
            word: word,
            answer: "\(word) answer",
            dictionaryTags: nil,
            dictionaryFrequency: nil,
            location: "",
            context: "",
            createdAt: createdAt,
            srs: srs ?? VocabularySRSState.initial(createdAt: createdAt)
        )
    }
}
