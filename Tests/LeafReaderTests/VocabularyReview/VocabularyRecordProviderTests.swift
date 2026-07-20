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
        assert(grouped.forms.map(\.surface) == ["Übersende", "übersendet"], "the group should expose unique inflected surface forms")
        assert(grouped.occurrences.map(\.id) == ["earlier", "later", "inflected"], "occurrences should sort by page before creation time")
        assert(grouped.occurrences.map(\.pageIndex) == [0, 2, 3], "navigation models should retain every page index")
        assert(grouped.occurrences.map(\.surfaceForm) == ["übersende", "Übersende", "übersendet"], "navigation models should retain every exact surface form")
        assert(grouped.occurrences[0].bounds?.cgRect == earlier.bounds.cgRect, "navigation models should retain exact PDF bounds")
        assert(grouped.occurrences[0].context == earlier.context, "navigation models should retain selectable context text")

        // MARK: - Labels flow through the provider

        // End-to-end check that a saved German occurrence reaches the view model
        // carrying its grammatical label, using the same production call path
        // the reader and library both render from.
        let participle = pdfRecord(
            id: "participle",
            word: "gehen",
            lemma: "gehen",
            surfaceForm: "gegangen",
            pageIndex: 5,
            bounds: CGRect(x: 20, y: 500, width: 80, height: 14),
            context: "Er ist gestern nach Hause gegangen.",
            createdAt: 5
        )
        let plural = pdfRecord(
            id: "plural",
            word: "Buch",
            lemma: "Buch",
            surfaceForm: "Bücher",
            pageIndex: 6,
            bounds: CGRect(x: 20, y: 480, width: 80, height: 14),
            context: "Die Bücher liegen dort.",
            createdAt: 6
        )
        let englishRecord = pdfRecord(
            id: "english",
            word: "house",
            lemma: "house",
            surfaceForm: "houses",
            pageIndex: 7,
            bounds: CGRect(x: 20, y: 460, width: 80, height: 14),
            context: "The houses are very old.",
            createdAt: 7
        )

        let labeled = VocabularyRecordProvider.records(
            documentKind: .pdf,
            pdfRecords: [participle, plural, englishRecord],
            webRecords: [],
            pdfContext: { $0.context ?? "" }
        )

        guard let verb = labeled.first(where: { $0.word == "gehen" }),
              let noun = labeled.first(where: { $0.word == "Buch" }),
              let english = labeled.first(where: { $0.word == "house" }) else {
            fputs("VocabularyRecordProviderTests failed: labeled records missing\n", stderr)
            exit(1)
        }
        assert(
            verb.forms.first?.label == .partizipII,
            "a saved German participle should reach the view model labeled Partizip II"
        )
        assert(
            noun.forms.first?.label == .plural,
            "a saved German plural should reach the view model labeled Plural"
        )
        assert(
            english.forms.first?.label == nil,
            "an English record must reach the view model with no German label"
        )

        // MARK: - Form merging

        let merged = VocabularyFormMerger.merged([
            VocabularyForm(surface: "gegangen", label: .partizipII, occurrenceCount: 1),
            VocabularyForm(surface: "ging", label: .finiteVerb, occurrenceCount: 1),
            VocabularyForm(surface: "Gegangen", label: nil, occurrenceCount: 2)
        ])
        assert(
            merged.map(\.surface) == ["gegangen", "ging"],
            "forms differing only by case should merge under the first spelling seen"
        )
        assert(
            merged[0].occurrenceCount == 3,
            "merging forms should sum their occurrence counts"
        )
        assert(
            merged[0].label == .partizipII,
            "a resolved label should survive merging with an unlabeled duplicate"
        )

        let labelRecovered = VocabularyFormMerger.merged([
            VocabularyForm(surface: "Bücher", label: nil, occurrenceCount: 1),
            VocabularyForm(surface: "Bücher", label: .plural, occurrenceCount: 1)
        ])
        assert(
            labelRecovered.count == 1 && labelRecovered[0].label == .plural,
            "an unlabeled form should adopt a label supplied by a later duplicate"
        )

        assert(
            VocabularyFormMerger.merged([VocabularyForm(surface: "   ")]).isEmpty,
            "blank surface forms should be dropped rather than shown as empty entries"
        )

        assert(
            VocabularyForm(surface: "gegangen", label: .partizipII).displayText
                == "gegangen (\(GermanFormLabel.partizipII.displayName))",
            "a labeled form should render its grammatical label"
        )
        assert(
            VocabularyForm(surface: "gegangen").displayText == "gegangen",
            "an unlabeled form should render as the bare surface form"
        )

        print("VocabularyRecordProviderTests passed")
    }
}
