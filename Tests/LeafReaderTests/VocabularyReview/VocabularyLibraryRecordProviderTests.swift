import Cocoa
import Foundation
import LeafReaderCore

private func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("VocabularyLibraryRecordProviderTests failed: \(message)\n", stderr)
        exit(1)
    }
}

private func record(
    id: String,
    word: String,
    language: VocabularyLanguageID? = nil,
    lemma: String? = nil,
    lexicalKey: String? = nil,
    partOfSpeech: VocabularyPartOfSpeech? = nil,
    surfaceForm: String? = nil,
    answer: String,
    location: String,
    context: String,
    createdAt: TimeInterval
) -> VocabularyExportRecord {
    let date = Date(timeIntervalSince1970: createdAt)
    return VocabularyExportRecord(
        ids: [id],
        word: word,
        language: language,
        lemma: lemma,
        lexicalKey: lexicalKey,
        partOfSpeech: partOfSpeech,
        forms: [VocabularyForm(surface: surfaceForm ?? word)],
        answer: answer,
        dictionaryTags: nil,
        dictionaryFrequency: nil,
        location: location,
        context: context,
        createdAt: date,
        srs: VocabularySRSState.initial(createdAt: date),
        occurrences: [
            VocabularyOccurrence(
                id: id,
                pageIndex: nil,
                bounds: nil,
                location: location,
                surfaceForm: surfaceForm ?? word,
                context: context,
                createdAt: date
            )
        ]
    )
}

@main
struct VocabularyLibraryRecordProviderTestRunner {
    static func main() {
        let firstURL = URL(fileURLWithPath: "/tmp/first.pdf")
        let secondURL = URL(fileURLWithPath: "/tmp/second.epub")
        let sources = [
            VocabularyLibrarySource(
                documentURL: firstURL,
                documentTitle: "First",
                documentKind: .pdf,
                records: [record(
                    id: "pdf-1",
                    word: "Überlegen",
                    language: .german,
                    lemma: "überlegen",
                    lexicalKey: "de|überlegen|verb|",
                    partOfSpeech: .verb,
                    surfaceForm: "Überlegen",
                    answer: "to consider",
                    location: "p. 4",
                    context: "Wir müssen uns das noch überlegen.",
                    createdAt: 10
                )]
            ),
            VocabularyLibrarySource(
                documentURL: secondURL,
                documentTitle: "Second",
                documentKind: .epub,
                records: [record(
                    id: "web-1",
                    word: "überlegte",
                    language: .german,
                    lemma: "überlegen",
                    lexicalKey: "de|überlegen|verb|",
                    partOfSpeech: .verb,
                    surfaceForm: "überlegte",
                    answer: "to think over carefully",
                    location: "42%",
                    context: "Sie wollte den Vorschlag überlegen.",
                    createdAt: 20
                )]
            )
        ]

        let records = VocabularyLibraryRecordProvider.records(sources: sources)
        assert(records.count == 1, "matching words should aggregate across documents")
        guard let word = records.first else { exit(1) }
        assert(word.occurrences.count == 2, "every source occurrence should remain available")
        assert(word.sourceCount == 2, "source count should reflect unique files")
        assert(word.answer == "to think over carefully", "the newest non-empty definition should win")
        assert(word.occurrences.map(\.recordID) == ["pdf-1", "web-1"], "occurrences should retain navigable record IDs")
        assert(word.forms.map(\.surface) == ["Überlegen", "überlegte"], "library grouping should retain unique inflected forms")
        assert(word.occurrences.map(\.surfaceForm) == ["Überlegen", "überlegte"], "library occurrences should retain exact forms")
        assert(word.occurrences.map(\.documentURL) == [firstURL, secondURL], "occurrences should retain source file URLs")
        assert(word.occurrences.map(\.context) == [
            "Wir müssen uns das noch überlegen.",
            "Sie wollte den Vorschlag überlegen."
        ], "occurrences should retain their document context")

        let englishGift = VocabularyLibrarySource(
            documentURL: URL(fileURLWithPath: "/tmp/english.pdf"),
            documentTitle: "English",
            documentKind: .pdf,
            records: [record(
                id: "en-gift",
                word: "Gift",
                language: .english,
                lemma: "gift",
                answer: "present",
                location: "p. 1",
                context: "This gift is for you.",
                createdAt: 1
            )]
        )
        let germanGift = VocabularyLibrarySource(
            documentURL: URL(fileURLWithPath: "/tmp/german.pdf"),
            documentTitle: "German",
            documentKind: .pdf,
            records: [record(
                id: "de-gift",
                word: "Gift",
                language: .german,
                lemma: "gift",
                answer: "poison",
                location: "p. 1",
                context: "Das Gift ist gefährlich.",
                createdAt: 2
            )]
        )
        let languageScoped = VocabularyLibraryRecordProvider.records(sources: [englishGift, germanGift])
        assert(languageScoped.count == 2, "known-different languages must never merge by spelling or lemma")
        assert(Set(languageScoped.compactMap(\.language)) == [.english, .german], "library records should preserve known language identity")

        let germanUnresolvedElsewhere = VocabularyLibrarySource(
            documentURL: URL(fileURLWithPath: "/tmp/german-elsewhere.pdf"),
            documentTitle: "German Elsewhere",
            documentKind: .pdf,
            records: [record(
                id: "de-gift-elsewhere",
                word: "Gift",
                language: .german,
                lemma: "gift",
                answer: "poison",
                location: "p. 3",
                context: "Gift bleibt gefährlich.",
                createdAt: 3
            )]
        )
        let sameLanguageUnresolved = VocabularyLibraryRecordProvider.records(sources: [germanGift, germanUnresolvedElsewhere])
        assert(sameLanguageUnresolved.count == 2, "known language plus lemma without a validated lexical key must remain document-scoped")

        let unknownFirst = VocabularyLibrarySource(
            documentURL: URL(fileURLWithPath: "/tmp/unknown-a.pdf"),
            documentTitle: "Unknown A",
            documentKind: .pdf,
            records: [record(
                id: "unknown-a",
                word: "die",
                lemma: "die",
                answer: "",
                location: "p. 1",
                context: "",
                createdAt: 1
            )]
        )
        let unknownSecond = VocabularyLibrarySource(
            documentURL: URL(fileURLWithPath: "/tmp/unknown-b.pdf"),
            documentTitle: "Unknown B",
            documentKind: .pdf,
            records: [record(
                id: "unknown-b",
                word: "die",
                lemma: "die",
                answer: "",
                location: "p. 2",
                context: "",
                createdAt: 2
            )]
        )
        let unknownScoped = VocabularyLibraryRecordProvider.records(sources: [unknownFirst, unknownSecond])
        assert(unknownScoped.count == 2, "unresolved records from unrelated documents must not merge by spelling alone")

        print("VocabularyLibraryRecordProviderTests passed")
    }
}
