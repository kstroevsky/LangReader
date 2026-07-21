import Foundation

struct VocabularyLibrarySource {
    let documentURL: URL
    let documentTitle: String
    let documentKind: ReaderDocumentKind
    let records: [VocabularyExportRecord]
}

struct VocabularyLibraryOccurrence {
    let recordID: String
    let documentURL: URL
    let documentTitle: String
    let documentKind: ReaderDocumentKind
    let location: String
    let surfaceForm: String?
    let context: String
    let createdAt: Date
}

struct VocabularyLibraryRecord {
    let id: String
    let word: String
    let lemma: String?
    let forms: [VocabularyForm]
    let answer: String
    let dictionaryTags: String?
    let dictionaryFrequency: Int?
    let occurrences: [VocabularyLibraryOccurrence]

    var latestCreatedAt: Date {
        occurrences.map(\.createdAt).max() ?? .distantPast
    }

    var sourceCount: Int {
        Set(occurrences.map { $0.documentURL.standardizedFileURL.path }).count
    }
}

enum VocabularyLibraryRecordProvider {
    static func records(sources: [VocabularyLibrarySource]) -> [VocabularyLibraryRecord] {
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
