import Foundation

package struct VocabularyOccurrence: Equatable {
    package let id: String
    package let pageIndex: Int?
    package let bounds: StoredPDFWordRect?
    package let location: String
    package let surfaceForm: String?
    package let context: String
    package let createdAt: Date

    package init(
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
package struct VocabularyForm: Equatable {
    package let surface: String
    package let label: GermanFormLabel?
    package let occurrenceCount: Int

    package init(surface: String, label: GermanFormLabel? = nil, occurrenceCount: Int = 1) {
        self.surface = surface
        self.label = label
        self.occurrenceCount = occurrenceCount
    }

    package var displayText: String {
        guard let label else { return surface }
        return "\(surface) (\(label.displayName))"
    }
}

package enum VocabularyFormMerger {
    /// Collapses repeated surface forms, summing their occurrence counts and
    /// keeping the first label that resolved. First-seen order is preserved so
    /// the display stays stable between refreshes.
    package static func merged(_ forms: [VocabularyForm]) -> [VocabularyForm] {
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

package struct VocabularyExportRecord {
    package let ids: [String]
    package let word: String
    package let lemma: String?
    package let forms: [VocabularyForm]
    package let answer: String
    package let dictionaryTags: String?
    package let dictionaryFrequency: Int?
    package let location: String
    package let context: String
    package let createdAt: Date
    package let srs: VocabularySRSState
    package let occurrences: [VocabularyOccurrence]

    package init(
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

    package func withDictionaryMetadata(tags: String? = nil, frequency: Int? = nil) -> VocabularyExportRecord {
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
