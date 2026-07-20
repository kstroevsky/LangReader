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

/// An observed surface form of a vocabulary entry, with its grammatical label
/// when one could be determined.
///
/// `label` is nil whenever the form could not be identified with confidence —
/// non-German text, or a form that is genuinely ambiguous such as `Autos`,
/// which is both a plural and a genitive singular. Callers render unlabeled
/// forms plainly rather than guessing.
struct VocabularyForm: Equatable {
    let surface: String
    let label: GermanFormLabel?
    let occurrenceCount: Int

    init(surface: String, label: GermanFormLabel? = nil, occurrenceCount: Int = 1) {
        self.surface = surface
        self.label = label
        self.occurrenceCount = occurrenceCount
    }

    var displayText: String {
        guard let label else { return surface }
        return "\(surface) (\(label.displayName))"
    }
}

enum VocabularyFormMerger {
    /// Collapses repeated surface forms, summing their occurrence counts and
    /// keeping the first label that resolved. First-seen order is preserved so
    /// the display stays stable between refreshes.
    static func merged(_ forms: [VocabularyForm]) -> [VocabularyForm] {
        var order: [String] = []
        var byKey: [String: VocabularyForm] = [:]

        for form in forms {
            let key = VocabularyTextPolicy.canonicalVocabularyKey(form.surface)
            guard !key.isEmpty else { continue }
            guard let existing = byKey[key] else {
                order.append(key)
                byKey[key] = form
                continue
            }
            byKey[key] = VocabularyForm(
                surface: existing.surface,
                label: existing.label ?? form.label,
                occurrenceCount: existing.occurrenceCount + form.occurrenceCount
            )
        }
        return order.compactMap { byKey[$0] }
    }
}

struct VocabularyExportRecord {
    let ids: [String]
    let word: String
    let lemma: String?
    let forms: [VocabularyForm]
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
        forms: [VocabularyForm] = [],
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
