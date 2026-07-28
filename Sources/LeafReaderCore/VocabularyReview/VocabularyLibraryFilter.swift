import Foundation
import LeafReaderCore

/// Which records the vocabulary library shows, in what order, and what stays
/// selected while the list changes underneath.
///
/// This used to run inside the library window's `applyFilters`, reading the
/// search field and source popup directly, so none of it could be exercised
/// without building a window — including the parts most likely to be wrong:
/// diacritic folding, which fields are searched, and whether the user's
/// selection survives a filter change.
package enum VocabularyLibraryFilter {
    package enum SortOrder: Int {
        case recent = 0
        case alphabetical = 1
    }

    /// Case- and diacritic-insensitive, because the library holds words in
    /// languages the user is still learning: someone reading German should find
    /// "Engpässen" by typing "engpassen", and search that only matched exact
    /// accents would look broken to them.
    package static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    /// Everything a query is matched against for one record.
    ///
    /// Deliberately wide: a word is often easier to recall by the sentence it
    /// was met in, or by the document it came from, than by its dictionary
    /// form — so contexts, titles and inflected forms are all searchable.
    package static func searchableText(for record: VocabularyLibraryRecord) -> String {
        var parts = [record.word, record.answer, record.dictionaryTags ?? ""]
        parts.append(contentsOf: record.forms.map(\.surface))
        for occurrence in record.occurrences {
            parts.append(occurrence.context)
            parts.append(occurrence.documentTitle)
            parts.append(occurrence.location)
        }
        return normalized(parts.joined(separator: "\n"))
    }

    package static func matchesSource(_ record: VocabularyLibraryRecord, sourcePath: String?) -> Bool {
        guard let sourcePath else { return true }
        return record.occurrences.contains {
            $0.documentURL.standardizedFileURL.path == sourcePath
        }
    }

    /// The records to show, filtered and sorted.
    package static func apply(
        records: [VocabularyLibraryRecord],
        query: String,
        sourcePath: String?,
        sortOrder: SortOrder
    ) -> [VocabularyLibraryRecord] {
        let normalizedQuery = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
        let filtered = records.filter { record in
            guard matchesSource(record, sourcePath: sourcePath) else { return false }
            guard !normalizedQuery.isEmpty else { return true }
            return searchableText(for: record).contains(normalizedQuery)
        }
        return sorted(filtered, by: sortOrder)
    }

    package static func sorted(
        _ records: [VocabularyLibraryRecord],
        by sortOrder: SortOrder
    ) -> [VocabularyLibraryRecord] {
        switch sortOrder {
        case .recent:
            // Ties broken alphabetically so the order is stable: several words
            // saved from one page share a timestamp, and a list that reshuffles
            // on every reload is unusable.
            return records.sorted {
                if $0.latestCreatedAt != $1.latestCreatedAt {
                    return $0.latestCreatedAt > $1.latestCreatedAt
                }
                return $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending
            }
        case .alphabetical:
            return records.sorted {
                $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending
            }
        }
    }

    /// Which row to select after the list changed.
    ///
    /// Keeps the selected word if it survived the filter, so typing does not
    /// yank the detail pane away mid-read; otherwise falls back to the first
    /// row, and to nothing when the filter matched nothing.
    package static func selectionRow(
        in records: [VocabularyLibraryRecord],
        preferredID: String?
    ) -> Int? {
        if let preferredID, let index = records.firstIndex(where: { $0.id == preferredID }) {
            return index
        }
        return records.isEmpty ? nil : 0
    }

    package static func summaryText(matchCount: Int, totalCount: Int) -> String {
        AppText.localized(
            "\(matchCount) / \(totalCount) 个单词",
            "\(matchCount) of \(totalCount) words"
        )
    }
}
