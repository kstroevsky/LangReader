import Foundation

struct VocabularyOccurrence: Equatable {
    let id: String
    let pageIndex: Int?
    let bounds: StoredPDFWordRect?
    let location: String
    let context: String
    let createdAt: Date
}

struct VocabularyExportRecord {
    let ids: [String]
    let word: String
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
