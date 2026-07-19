import Cocoa
import Foundation

struct StoredPDFWordRecord {
    let id: String
    let word: String
    var lemma: String? = nil
    var surfaceForm: String? = nil
    let pageIndex: Int
    let bounds: StoredPDFWordRect
    var context: String?
    var question: String
    var answer: String
    var dictionaryTags: String?
    var dictionaryFrequency: Int?
    let createdAt: Date
    var srs: VocabularySRSState?

    var occurrenceSurfaceForm: String {
        surfaceForm ?? word
    }
}

struct StoredWebWordRecord {
    let id: String
    let word: String
    let context: String
    let occurrenceIndex: Int?
    let scrollProgress: Double
    var question: String
    var answer: String
    var dictionaryTags: String?
    var dictionaryFrequency: Int?
    let createdAt: Date
    var srs: VocabularySRSState?
}

private func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("VocabularyRecordProviderTests failed: \(message)\n", stderr)
        exit(1)
    }
}

private func pdfRecord(
    id: String,
    word: String,
    lemma: String? = nil,
    surfaceForm: String? = nil,
    pageIndex: Int,
    bounds: CGRect,
    context: String,
    answer: String = "",
    createdAt: TimeInterval
) -> StoredPDFWordRecord {
    StoredPDFWordRecord(
        id: id,
        word: word,
        lemma: lemma,
        surfaceForm: surfaceForm,
        pageIndex: pageIndex,
        bounds: StoredPDFWordRect(bounds),
        context: context,
        question: "",
        answer: answer,
        dictionaryTags: nil,
        dictionaryFrequency: nil,
        createdAt: Date(timeIntervalSince1970: createdAt),
        srs: nil
    )
}

@main
struct VocabularyRecordProviderTestRunner {
    static func main() {
        let later = pdfRecord(
            id: "later",
            word: "Übersende",
            lemma: "übersenden",
            surfaceForm: "Übersende",
            pageIndex: 2,
            bounds: CGRect(x: 180, y: 500, width: 70, height: 14),
            context: "Später: Übersende die Unterlagen.",
            createdAt: 1
        )
        let earlier = pdfRecord(
            id: "earlier",
            word: "übersende",
            lemma: "übersenden",
            surfaceForm: "übersende",
            pageIndex: 0,
            bounds: CGRect(x: 40, y: 700, width: 70, height: 14),
            context: "Zuerst übersende ich die Unterlagen.",
            createdAt: 2
        )
        let noDiacritic = pdfRecord(
            id: "plain",
            word: "ubersende",
            pageIndex: 1,
            bounds: CGRect(x: 50, y: 600, width: 70, height: 14),
            context: "A deliberately different spelling.",
            createdAt: 3
        )
        let inflected = pdfRecord(
            id: "inflected",
            word: "übersendet",
            lemma: "übersenden",
            surfaceForm: "übersendet",
            pageIndex: 3,
            bounds: CGRect(x: 70, y: 550, width: 70, height: 14),
            context: "Sie übersendet die Unterlagen.",
            createdAt: 4
        )


        let records = VocabularyRecordProvider.records(
            documentKind: .pdf,
            pdfRecords: [later, earlier, noDiacritic, inflected],
            webRecords: [],
            pdfContext: { $0.context ?? "" }
        )

        assert(records.count == 2, "case-insensitive German forms should group while diacritics remain significant")
        guard let grouped = records.first(where: {
            VocabularyTextPolicy.canonicalVocabularyKey($0.word)
                == VocabularyTextPolicy.canonicalVocabularyKey("übersende")
        }) else {
            fputs("VocabularyRecordProviderTests failed: grouped German word missing\n", stderr)
            exit(1)
        }

        assert(grouped.word == "Übersende", "the first selected capitalization should be preserved")
        assert(grouped.answer.isEmpty, "answerless saved words should remain in the vocabulary model")
        assert(grouped.forms == ["Übersende", "übersendet"], "the group should expose unique inflected surface forms")
        assert(grouped.occurrences.map(\.id) == ["earlier", "later", "inflected"], "occurrences should sort by page before creation time")
        assert(grouped.occurrences.map(\.pageIndex) == [0, 2, 3], "navigation models should retain every page index")
        assert(grouped.occurrences.map(\.surfaceForm) == ["übersende", "Übersende", "übersendet"], "navigation models should retain every exact surface form")
        assert(grouped.occurrences[0].bounds?.cgRect == earlier.bounds.cgRect, "navigation models should retain exact PDF bounds")
        assert(grouped.occurrences[0].context == earlier.context, "navigation models should retain selectable context text")

        print("VocabularyRecordProviderTests passed")
    }
}
