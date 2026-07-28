import Foundation
import LeafReaderCore

package struct VocabularyLibrarySource {
    package let documentURL: URL
    package let documentTitle: String
    package let documentKind: ReaderDocumentKind
    package let records: [VocabularyExportRecord]

    package init(
        documentURL: URL,
        documentTitle: String,
        documentKind: ReaderDocumentKind,
        records: [VocabularyExportRecord]
    ) {
        self.documentURL = documentURL
        self.documentTitle = documentTitle
        self.documentKind = documentKind
        self.records = records
    }
}

package struct VocabularyLibraryOccurrence {
    package let recordID: String
    package let documentURL: URL
    package let documentTitle: String
    package let documentKind: ReaderDocumentKind
    package let location: String
    package let surfaceForm: String?
    package let context: String
    package let createdAt: Date

    package init(
        recordID: String,
        documentURL: URL,
        documentTitle: String,
        documentKind: ReaderDocumentKind,
        location: String,
        surfaceForm: String?,
        context: String,
        createdAt: Date
    ) {
        self.recordID = recordID
        self.documentURL = documentURL
        self.documentTitle = documentTitle
        self.documentKind = documentKind
        self.location = location
        self.surfaceForm = surfaceForm
        self.context = context
        self.createdAt = createdAt
    }
}

package struct VocabularyLibraryRecord {
    package let id: String
    package let word: String
    package let lemma: String?
    package let forms: [VocabularyForm]
    package let answer: String
    package let dictionaryTags: String?
    package let dictionaryFrequency: Int?
    package let occurrences: [VocabularyLibraryOccurrence]

    package init(
        id: String,
        word: String,
        lemma: String?,
        forms: [VocabularyForm],
        answer: String,
        dictionaryTags: String?,
        dictionaryFrequency: Int?,
        occurrences: [VocabularyLibraryOccurrence]
    ) {
        self.id = id
        self.word = word
        self.lemma = lemma
        self.forms = forms
        self.answer = answer
        self.dictionaryTags = dictionaryTags
        self.dictionaryFrequency = dictionaryFrequency
        self.occurrences = occurrences
    }

    package var latestCreatedAt: Date {
        occurrences.map(\.createdAt).max() ?? .distantPast
    }

    package var sourceCount: Int {
        Set(occurrences.map { $0.documentURL.standardizedFileURL.path }).count
    }
}

package enum VocabularyLibraryRecordProvider {
    package static func records(sources: [VocabularyLibrarySource]) -> [VocabularyLibraryRecord] {
        typealias Entry = (source: VocabularyLibrarySource, record: VocabularyExportRecord)
        var grouped: [String: [Entry]] = [:]

        for source in sources {
            for record in source.records {
                let key = VocabularyTextPolicy.canonicalVocabularyKey(record.lemma ?? record.word)
                guard !key.isEmpty else { continue }
                grouped[key, default: []].append((source, record))
            }
        }

        return grouped.compactMap { key, entries in
            guard let first = entries.min(by: { $0.record.createdAt < $1.record.createdAt }) else {
                return nil
            }
            let answerEntry = entries
                .filter { !$0.record.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .max { $0.record.createdAt < $1.record.createdAt }
            let tags = entries
                .compactMap { $0.record.dictionaryTags?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            let frequency = entries.compactMap { $0.record.dictionaryFrequency }.min()
            // Surface forms recovered from occurrences carry no label of their
            // own; they are merged after the labeled forms so an existing label
            // always wins over a bare surface form for the same spelling.
            let forms = VocabularyFormMerger.merged(
                entries.flatMap(\.record.forms)
                    + entries.flatMap { entry in
                        entry.record.occurrences
                            .compactMap(\.surfaceForm)
                            .map { VocabularyForm(surface: $0, occurrenceCount: 0) }
                    }
            )
            let occurrences = entries.flatMap { entry in
                libraryOccurrences(source: entry.source, record: entry.record)
            }.sorted(by: occurrenceSort)

            return VocabularyLibraryRecord(
                id: key,
                word: VocabularyTextPolicy.normalizedVocabularyText(first.record.word),
                lemma: first.record.lemma,
                forms: forms,
                answer: answerEntry?.record.answer ?? "",
                dictionaryTags: tags,
                dictionaryFrequency: frequency,
                occurrences: occurrences
            )
        }.sorted {
            $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending
        }
    }

    private static func libraryOccurrences(
        source: VocabularyLibrarySource,
        record: VocabularyExportRecord
    ) -> [VocabularyLibraryOccurrence] {
        let occurrences = record.occurrences.isEmpty
            ? [VocabularyOccurrence(
                id: record.ids.first ?? "",
                pageIndex: nil,
                bounds: nil,
                location: record.location,
                context: record.context,
                createdAt: record.createdAt
            )]
            : record.occurrences

        return occurrences.map {
            VocabularyLibraryOccurrence(
                recordID: $0.id,
                documentURL: source.documentURL.standardizedFileURL,
                documentTitle: source.documentTitle,
                documentKind: source.documentKind,
                location: $0.location,
                surfaceForm: $0.surfaceForm ?? record.word,
                context: $0.context,
                createdAt: $0.createdAt
            )
        }
    }

    private static func occurrenceSort(
        _ lhs: VocabularyLibraryOccurrence,
        _ rhs: VocabularyLibraryOccurrence
    ) -> Bool {
        let titleOrder = lhs.documentTitle.localizedCaseInsensitiveCompare(rhs.documentTitle)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }
        if lhs.location != rhs.location {
            return lhs.location.localizedStandardCompare(rhs.location) == .orderedAscending
        }
        return lhs.createdAt < rhs.createdAt
    }
}
