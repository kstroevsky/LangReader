import Foundation

package struct VocabularyLearningOwnerID: Codable, Hashable, Sendable {
    package let rawValue: String

    package init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

package struct VocabularyOccurrence: Equatable {
    package let id: String
    package let learningOwnerID: VocabularyLearningOwnerID?
    package let language: VocabularyLanguageID?
    package let lemma: String?
    package let lexicalKey: String?
    package let partOfSpeech: VocabularyPartOfSpeech?
    package let pageIndex: Int?
    package let bounds: StoredPDFWordRect?
    package let location: String
    package let surfaceForm: String?
    package let context: String
    package let createdAt: Date

    package init(
        id: String,
        learningOwnerID: VocabularyLearningOwnerID? = nil,
        language: VocabularyLanguageID? = nil,
        lemma: String? = nil,
        lexicalKey: String? = nil,
        partOfSpeech: VocabularyPartOfSpeech? = nil,
        pageIndex: Int?,
        bounds: StoredPDFWordRect?,
        location: String,
        surfaceForm: String? = nil,
        context: String,
        createdAt: Date
    ) {
        self.id = id
        self.learningOwnerID = learningOwnerID
        self.language = language
        self.lemma = lemma
        self.lexicalKey = lexicalKey
        self.partOfSpeech = partOfSpeech
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
    package let learningOwnerIDs: [VocabularyLearningOwnerID]
    package let word: String
    package let language: VocabularyLanguageID?
    package let lemma: String?
    package let lexicalKey: String?
    package let partOfSpeech: VocabularyPartOfSpeech?
    package let forms: [VocabularyForm]
    package let answer: String
    package let dictionaryTags: String?
    package let dictionaryFrequency: Int?
    package let dictionaryFrequencyProvenance: VocabularyFrequencyProvenance?
    package let location: String
    package let context: String
    package let createdAt: Date
    package let srs: VocabularySRSState
    package let occurrences: [VocabularyOccurrence]

    package init(
        ids: [String],
        learningOwnerIDs: [VocabularyLearningOwnerID] = [],
        word: String,
        language: VocabularyLanguageID? = nil,
        lemma: String? = nil,
        lexicalKey: String? = nil,
        partOfSpeech: VocabularyPartOfSpeech? = nil,
        forms: [VocabularyForm] = [],
        answer: String,
        dictionaryTags: String?,
        dictionaryFrequency: Int?,
        dictionaryFrequencyProvenance: VocabularyFrequencyProvenance? = nil,
        location: String,
        context: String,
        createdAt: Date,
        srs: VocabularySRSState,
        occurrences: [VocabularyOccurrence] = []
    ) {
        self.ids = ids
        self.learningOwnerIDs = learningOwnerIDs
        self.word = word
        self.language = language
        self.lemma = lemma
        self.lexicalKey = lexicalKey
        self.partOfSpeech = partOfSpeech
        self.forms = forms
        self.answer = answer
        self.dictionaryTags = dictionaryTags
        self.dictionaryFrequency = dictionaryFrequency
        self.dictionaryFrequencyProvenance = dictionaryFrequencyProvenance
        self.location = location
        self.context = context
        self.createdAt = createdAt
        self.srs = srs
        self.occurrences = occurrences
    }

    package var verifiedDictionaryFrequency: Int? {
        guard let dictionaryFrequency,
              let provenance = dictionaryFrequencyProvenance,
              provenance.provider.supports(provenance.language),
              language == nil || language == provenance.language else {
            return nil
        }
        return dictionaryFrequency
    }

    package func withDictionaryMetadata(
        tags: String? = nil,
        frequency: Int? = nil,
        frequencyProvenance: VocabularyFrequencyProvenance? = nil
    ) -> VocabularyExportRecord {
        VocabularyExportRecord(
            ids: ids,
            learningOwnerIDs: learningOwnerIDs,
            word: word,
            language: language,
            lemma: lemma,
            lexicalKey: lexicalKey,
            partOfSpeech: partOfSpeech,
            forms: forms,
            answer: answer,
            dictionaryTags: tags ?? dictionaryTags,
            dictionaryFrequency: frequency ?? dictionaryFrequency,
            dictionaryFrequencyProvenance: frequency == nil
                ? dictionaryFrequencyProvenance
                : frequencyProvenance,
            location: location,
            context: context,
            createdAt: createdAt,
            srs: srs,
            occurrences: occurrences
        )
    }

    /// Stable aggregation identity for persisted/exported vocabulary. Resolved
    /// lexical identity wins. Any record without a validated lexical identity
    /// stays source-scoped when crossing document boundaries, even when its
    /// language is known; language + lemma alone is not enough evidence for a
    /// global lexical merge.
    package func identityGroupingKey(unresolvedScope: String? = nil) -> String? {
        if let lexicalKey = lexicalKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           !lexicalKey.isEmpty {
            return "lexical|\(lexicalKey)"
        }
        let lemmaKey = VocabularyTextPolicy.canonicalVocabularyKey(lemma ?? word)
        guard !lemmaKey.isEmpty else { return nil }
        if let unresolvedScope {
            let languageKey = language?.bcp47 ?? "unknown"
            return "unresolved|\(unresolvedScope)|\(languageKey)|\(lemmaKey)"
        }
        if let language {
            return "language|\(language.bcp47)|\(lemmaKey)"
        }
        return "language-unknown|\(lemmaKey)"
    }
}
