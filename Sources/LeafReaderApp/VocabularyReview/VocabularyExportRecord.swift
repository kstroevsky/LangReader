import Foundation

struct VocabularyOccurrence: Equatable {
    let id: String
    let pageIndex: Int?
    let bounds: StoredPDFWordRect?
    let location: String
    let surfaceForm: String?
    let context: String
    let createdAt: Date

    init(
        id: String,
        pageIndex: Int?,
        bounds: StoredPDFWordRect?,
        location: String,
        surfaceForm: String? = nil,
        context: String,
        createdAt: Date
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.bounds = bounds
        self.location = location
        self.surfaceForm = surfaceForm
        self.context = context
        self.createdAt = createdAt
    }
}

struct VocabularyExportRecord {
    let ids: [String]
    let word: String
    let lemma: String?
    let forms: [String]
    let answer: String
    let dictionaryTags: String?
    let dictionaryFrequency: Int?
    let location: String
    let context: String
    let createdAt: Date
    let srs: VocabularySRSState
    let occurrences: [VocabularyOccurrence]

    init(
        ids: [String],
        word: String,
        lemma: String? = nil,
        forms: [String] = [],
        answer: String,
        dictionaryTags: String?,
        dictionaryFrequency: Int?,
        location: String,
        context: String,
        createdAt: Date,
        srs: VocabularySRSState,
        occurrences: [VocabularyOccurrence] = []
    ) {
        self.ids = ids
        self.word = word
        self.lemma = lemma
        self.forms = forms
        self.answer = answer
        self.dictionaryTags = dictionaryTags
        self.dictionaryFrequency = dictionaryFrequency
        self.location = location
        self.context = context
        self.createdAt = createdAt
        self.srs = srs
        self.occurrences = occurrences
    }

    func withDictionaryMetadata(tags: String? = nil, frequency: Int? = nil) -> VocabularyExportRecord {
        VocabularyExportRecord(
            ids: ids,
            word: word,
            lemma: lemma,
            forms: forms,
            answer: answer,
            dictionaryTags: tags ?? dictionaryTags,
            dictionaryFrequency: frequency ?? dictionaryFrequency,
            location: location,
            context: context,
            createdAt: createdAt,
            srs: srs,
            occurrences: occurrences
        )
    }
}
