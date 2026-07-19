import Cocoa
import Foundation

private func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("VocabularyLibraryRecordProviderTests failed: \(message)\n", stderr)
        exit(1)
    }
}

private func record(
    id: String,
    word: String,
    answer: String,
    location: String,
    context: String,
    createdAt: TimeInterval
) -> VocabularyExportRecord {
    let date = Date(timeIntervalSince1970: createdAt)
    return VocabularyExportRecord(
        ids: [id],
        word: word,
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
                    word: "überlegen",
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
        assert(word.occurrences.map(\.documentURL) == [firstURL, secondURL], "occurrences should retain source file URLs")
        assert(word.occurrences.map(\.context) == [
            "Wir müssen uns das noch überlegen.",
            "Sie wollte den Vorschlag überlegen."
        ], "occurrences should retain their document context")

        print("VocabularyLibraryRecordProviderTests passed")
    }
}
