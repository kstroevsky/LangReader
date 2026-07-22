import Foundation

enum VocabularyLibraryFilterTests {
    static func testSearchIsCaseAndDiacriticInsensitive() throws {
        let record = makeRecord(id: "1", word: "Engpässen", createdAt: 100)
        let records = [record]

        for query in ["engpassen", "ENGPÄSSEN", "Engpässen", "pässe", "passe"] {
            try expectEqual(
                filtered(records, query: query).count,
                1,
                "query \"\(query)\" should match Engpässen"
            )
        }
        try expectEqual(filtered(records, query: "zzz").count, 0, "an unrelated query should match nothing")
    }

    static func testSearchCoversContextAndFormsNotJustTheWord() throws {
        let record = makeRecord(
            id: "1",
            word: "gehen",
            answer: "to go",
            tags: "verb",
            formSurfaces: ["ging", "gegangen"],
            context: "Wir sind nach Hause gegangen",
            documentTitle: "Reisebericht",
            location: "p. 12",
            createdAt: 100
        )
        let records = [record]

        // A word is often easier to recall by where it was met than by its
        // dictionary form, so all of these have to find it.
        for query in ["gehen", "to go", "verb", "ging", "gegangen", "nach Hause", "Reisebericht", "p. 12"] {
            try expectEqual(
                filtered(records, query: query).count,
                1,
                "query \"\(query)\" should find the record"
            )
        }
    }

    static func testBlankQueryMatchesEverything() throws {
        let records = [
            makeRecord(id: "1", word: "alpha", createdAt: 100),
            makeRecord(id: "2", word: "beta", createdAt: 200)
        ]
        try expectEqual(filtered(records, query: "").count, 2, "an empty query should not filter")
        try expectEqual(filtered(records, query: "   ").count, 2, "a whitespace query should not filter")
    }

    static func testSourceFilterRestrictsToOneDocument() throws {
        let a = makeRecord(id: "1", word: "alpha", documentPath: "/tmp/a.pdf", createdAt: 100)
        let b = makeRecord(id: "2", word: "beta", documentPath: "/tmp/b.pdf", createdAt: 200)
        let records = [a, b]

        try expectEqual(
            VocabularyLibraryFilter.apply(records: records, query: "", sourcePath: "/tmp/a.pdf", sortOrder: .recent).map(\.id),
            ["1"],
            "the source filter should keep only records from that document"
        )
        try expectEqual(
            VocabularyLibraryFilter.apply(records: records, query: "", sourcePath: nil, sortOrder: .recent).count,
            2,
            "no source filter should keep everything"
        )
        try expectEqual(
            VocabularyLibraryFilter.apply(records: records, query: "", sourcePath: "/tmp/missing.pdf", sortOrder: .recent).count,
            0,
            "an unknown source should match nothing"
        )
    }

    static func testRecentSortBreaksTiesAlphabetically() throws {
        // Words saved from one page share a timestamp; without a tie-break the
        // list reshuffles on every reload.
        let records = [
            makeRecord(id: "1", word: "zeta", createdAt: 500),
            makeRecord(id: "2", word: "alpha", createdAt: 500),
            makeRecord(id: "3", word: "newer", createdAt: 900)
        ]
        try expectEqual(
            VocabularyLibraryFilter.sorted(records, by: .recent).map(\.word),
            ["newer", "alpha", "zeta"],
            "recent sort should put newest first, then break ties alphabetically"
        )
        try expectEqual(
            VocabularyLibraryFilter.sorted(records, by: .recent).map(\.word),
            VocabularyLibraryFilter.sorted(records.reversed(), by: .recent).map(\.word),
            "recent sort should not depend on input order"
        )
    }

    static func testAlphabeticalSortIgnoresCase() throws {
        let records = [
            makeRecord(id: "1", word: "banana", createdAt: 100),
            makeRecord(id: "2", word: "Apple", createdAt: 200),
            makeRecord(id: "3", word: "cherry", createdAt: 300)
        ]
        try expectEqual(
            VocabularyLibraryFilter.sorted(records, by: .alphabetical).map(\.word),
            ["Apple", "banana", "cherry"],
            "alphabetical sort should be case-insensitive"
        )
    }

    static func testSelectionSurvivesFilteringWhenPossible() throws {
        let records = [
            makeRecord(id: "1", word: "alpha", createdAt: 100),
            makeRecord(id: "2", word: "beta", createdAt: 200)
        ]
        // Typing must not yank the detail pane away from the word being read.
        try expectEqual(
            VocabularyLibraryFilter.selectionRow(in: records, preferredID: "2"),
            1,
            "a surviving selection should stay selected"
        )
        try expectEqual(
            VocabularyLibraryFilter.selectionRow(in: records, preferredID: "gone"),
            0,
            "a selection that was filtered out should fall back to the first row"
        )
        try expectEqual(
            VocabularyLibraryFilter.selectionRow(in: records, preferredID: nil),
            0,
            "no preference should select the first row"
        )
        try expect(
            VocabularyLibraryFilter.selectionRow(in: [], preferredID: "1") == nil,
            "an empty list should select nothing"
        )
    }

    // MARK: Helpers

    private static func filtered(
        _ records: [VocabularyLibraryRecord],
        query: String
    ) -> [VocabularyLibraryRecord] {
        VocabularyLibraryFilter.apply(records: records, query: query, sourcePath: nil, sortOrder: .recent)
    }

    private static func makeRecord(
        id: String,
        word: String,
        answer: String = "",
        tags: String? = nil,
        formSurfaces: [String] = [],
        context: String = "",
        documentTitle: String = "Doc",
        location: String = "",
        documentPath: String = "/tmp/doc.pdf",
        createdAt: TimeInterval
    ) -> VocabularyLibraryRecord {
        VocabularyLibraryRecord(
            id: id,
            word: word,
            lemma: nil,
            forms: formSurfaces.map { VocabularyForm(surface: $0, label: nil) },
            answer: answer,
            dictionaryTags: tags,
            dictionaryFrequency: nil,
            occurrences: [
                VocabularyLibraryOccurrence(
                    recordID: id,
                    documentURL: URL(fileURLWithPath: documentPath),
                    documentTitle: documentTitle,
                    documentKind: .pdf,
                    location: location,
                    surfaceForm: nil,
                    context: context,
                    createdAt: Date(timeIntervalSince1970: createdAt)
                )
            ]
        )
    }
}
