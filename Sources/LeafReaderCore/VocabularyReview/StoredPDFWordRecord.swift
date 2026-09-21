import Foundation

/// Persisted semantic data for one vocabulary occurrence in a PDF.
///
/// The optional rectangle is retained as a renderer cache, while `textAnchor`
/// is the stable identity used when source text is available. The model belongs
/// to Core; PDFSelection-to-record conversion remains in the app adapter.
package struct StoredPDFWordRecord: Codable, Sendable {
    package let id: String
    package var vocabularyID: String?
    package var word: String
    package var lemma: String?
    package var lexicalKey: String?
    package var partOfSpeech: VocabularyPartOfSpeech?
    package var surfaceForm: String?
    package let pageIndex: Int
    package let bounds: StoredPDFWordRect
    package var textAnchor: TextQuoteAnchor?
    package var context: String?
    package var question: String
    package var answer: String
    package var dictionaryTags: String?
    package var dictionaryFrequency: Int?
    package let createdAt: Date
    package var srs: VocabularySRSState?

    package init(
        id: String,
        vocabularyID: String? = nil,
        word: String,
        lemma: String? = nil,
        lexicalKey: String? = nil,
        partOfSpeech: VocabularyPartOfSpeech? = nil,
        surfaceForm: String? = nil,
        pageIndex: Int,
        bounds: StoredPDFWordRect,
        textAnchor: TextQuoteAnchor? = nil,
        context: String? = nil,
        question: String,
        answer: String,
        dictionaryTags: String? = nil,
        dictionaryFrequency: Int? = nil,
        createdAt: Date,
        srs: VocabularySRSState? = nil
    ) {
        self.id = id
        self.vocabularyID = vocabularyID
        self.word = word
        self.lemma = lemma
        self.lexicalKey = lexicalKey
        self.partOfSpeech = partOfSpeech
        self.surfaceForm = surfaceForm
        self.pageIndex = pageIndex
        self.bounds = bounds
        self.textAnchor = textAnchor
        self.context = context
        self.question = question
        self.answer = answer
        self.dictionaryTags = dictionaryTags
        self.dictionaryFrequency = dictionaryFrequency
        self.createdAt = createdAt
        self.srs = srs
    }

    package var vocabularyGroupingText: String {
        guard let lemma = lemma?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lemma.isEmpty else { return word }
        return lemma
    }

    package var occurrenceSurfaceForm: String {
        guard let surfaceForm = surfaceForm?.trimmingCharacters(in: .whitespacesAndNewlines),
              !surfaceForm.isEmpty else { return word }
        return surfaceForm
    }

    package var matchesSavedSurfaceForm: Bool {
        VocabularyTextPolicy.canonicalVocabularyKey(occurrenceSurfaceForm)
            == VocabularyTextPolicy.canonicalVocabularyKey(word)
    }

    /// Stable occurrence identity used by persistence and save deduplication.
    package var occurrenceKey: String {
        if let textAnchor {
            return "text:\(textAnchor.unitOrdinal):\(textAnchor.sourceStart):\(textAnchor.sourceLength)"
        }
        let rect = bounds.cgRect
        return "\(pageIndex):\(Int(rect.origin.x.rounded())):\(Int(rect.origin.y.rounded())):\(Int(rect.width.rounded())):\(Int(rect.height.rounded()))"
    }
}
