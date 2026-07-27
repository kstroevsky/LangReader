import Foundation
import LeafReaderCore

enum VocabularyOccurrenceGroupingTests {
    static func testGroupsCollapseSpellingsThatDifferOnlyByCase() throws {
        let record = makeRecord(word: "kommen", forms: [])
        let groups = VocabularyOccurrenceGrouping.formGroups(
            record: record,
            occurrences: [
                makeOccurrence(surface: "Kommen"),
                makeOccurrence(surface: "kommen"),
                makeOccurrence(surface: "KOMMEN")
            ]
        )

        try expectEqual(groups.count, 1, "spellings differing only by case should share one tab")
        try expectEqual(groups[0].count, 3, "the tab count should include every occurrence")
        // The first spelling met is the one shown, so the tab reads the way the
        // reader actually saw the word.
        try expectEqual(groups[0].surface, "Kommen", "the first-seen spelling should label the tab")
    }

    static func testGroupsFollowFirstEncounterOrder() throws {
        let record = makeRecord(word: "kommen", forms: [])
        let groups = VocabularyOccurrenceGrouping.formGroups(
            record: record,
            occurrences: [
                makeOccurrence(surface: "zzz"),
                makeOccurrence(surface: "aaa"),
                makeOccurrence(surface: "zzz"),
                makeOccurrence(surface: "mmm")
            ]
        )

        // Not alphabetical: tabs follow the order the forms were met, so a tab
        // does not jump position when a new occurrence is saved.
        try expectEqual(groups.map(\.surface), ["zzz", "aaa", "mmm"], "tabs should keep first-encounter order")
        try expectEqual(groups.map(\.count), [2, 1, 1], "counts should follow the same order")
    }

    static func testOccurrenceWithoutSurfaceFormFallsBackToTheSavedWord() throws {
        // Occurrences saved before surface-form tracking have no spelling
        // recorded; dropping them would make the tab counts disagree with the
        // rows they reveal.
        let record = makeRecord(word: "gehen", forms: [])
        let groups = VocabularyOccurrenceGrouping.formGroups(
            record: record,
            occurrences: [makeOccurrence(surface: nil), makeOccurrence(surface: "gehen")]
        )

        try expectEqual(groups.count, 1, "a missing spelling should fall back to the saved word")
        try expectEqual(groups[0].count, 2, "the fallback occurrence should still be counted")
        try expectEqual(groups[0].surface, "gehen", "the fallback should use the record's word")
    }

    static func testBlankSurfacesAreSkippedRatherThanFormingAnEmptyTab() throws {
        let record = makeRecord(word: "gehen", forms: [])
        let groups = VocabularyOccurrenceGrouping.formGroups(
            record: record,
            occurrences: [makeOccurrence(surface: "   "), makeOccurrence(surface: "ging")]
        )

        try expectEqual(groups.map(\.surface), ["ging"], "a blank spelling should not create a tab")
    }

    static func testCountsComeFromOccurrencesNotTheFormList() throws {
        // The form list is built from a dictionary; the occurrences are what is
        // really in the document. A form the reader never met must not appear.
        let record = makeRecord(
            word: "kommen",
            forms: [
                VocabularyForm(surface: "kommen", label: .infinitiv),
                VocabularyForm(surface: "kaeme", label: .finiteVerb)
            ]
        )
        let groups = VocabularyOccurrenceGrouping.formGroups(
            record: record,
            occurrences: [makeOccurrence(surface: "kommen"), makeOccurrence(surface: "kommen")]
        )

        try expectEqual(groups.count, 1, "a form with no occurrences should not get a tab")
        try expectEqual(groups[0].count, 2, "the count should come from the occurrences")
        try expectEqual(groups[0].label, .infinitiv, "the matching form's label should be attached")
    }

    static func testLabelsMatchAcrossCaseAndTakeTheFirstOnConflict() throws {
        let record = makeRecord(
            word: "kommen",
            forms: [
                VocabularyForm(surface: "Kommen", label: .infinitiv),
                VocabularyForm(surface: "kommen", label: .finiteVerb)
            ]
        )
        let labels = VocabularyOccurrenceGrouping.labels(for: record)
        let key = VocabularyTextPolicy.canonicalVocabularyKey("kommen")

        try expectEqual(labels.count, 1, "forms differing only by case should share one label entry")
        // First wins, so a tab does not flip its label between reloads.
        try expectEqual(labels[key], .infinitiv, "the first label should win a conflict")
    }

    static func testNoOccurrencesProducesNoTabs() throws {
        let record = makeRecord(word: "kommen", forms: [VocabularyForm(surface: "kommen", label: .infinitiv)])
        try expect(
            VocabularyOccurrenceGrouping.formGroups(record: record, occurrences: []).isEmpty,
            "a word with no occurrences should produce no tabs"
        )
    }

    // MARK: Helpers

    private static func makeRecord(word: String, forms: [VocabularyForm]) -> VocabularyLibraryRecord {
        VocabularyLibraryRecord(
            id: "record",
            word: word,
            lemma: nil,
            forms: forms,
            answer: "",
            dictionaryTags: nil,
            dictionaryFrequency: nil,
            occurrences: []
        )
    }

    private static func makeOccurrence(surface: String?) -> VocabularyLibraryOccurrence {
        VocabularyLibraryOccurrence(
            recordID: "record",
            documentURL: URL(fileURLWithPath: "/tmp/doc.pdf"),
            documentTitle: "Doc",
            documentKind: .pdf,
            location: "p. 1",
            surfaceForm: surface,
            context: "",
            createdAt: Date(timeIntervalSince1970: 100)
        )
    }
}
