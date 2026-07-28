import Foundation

package struct ReadingNoteListRowViewModel: Equatable {
    package let id: String
    package let locationText: String
    package let titleText: String
    package let isFavorite: Bool
}

package enum ReadingNoteListPresenter {
    package static func sortedNotes(_ notes: [ReadingNote]) -> [ReadingNote] {
        notes.sortedForReadingNoteList()
    }

    package static func rows(for notes: [ReadingNote]) -> [ReadingNoteListRowViewModel] {
        sortedNotes(notes).map(row)
    }

    package static func filteredNotes(_ notes: [ReadingNote], query: String) -> [ReadingNote] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return sortedNotes(notes)
        }
        return sortedNotes(notes).filter { note in
            searchableText(for: note)
                .localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    package static func rows(for notes: [ReadingNote], query: String) -> [ReadingNoteListRowViewModel] {
        filteredNotes(notes, query: query).map(row)
    }

    package static func summaryText(noteCount: Int) -> String {
        AppText.localized("共 \(noteCount) 条笔记", "\(noteCount) note(s)")
    }

    /// The summary shown while a search is narrowing the list.
    ///
    /// An empty query is not a search, so it falls back to the plain count
    /// rather than reading "12 of 12".
    package static func summaryText(matchCount: Int, totalCount: Int, query: String) -> String {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return summaryText(noteCount: matchCount)
        }
        return AppText.localized(
            "找到 \(matchCount) / \(totalCount) 条笔记",
            "\(matchCount) of \(totalCount) note(s)"
        )
    }

    /// What to show when the list has no rows — which reads differently when a
    /// search excluded everything than when there are simply no notes.
    package static func emptyStateText(query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppText.localized("当前书还没有阅读笔记。", "No reading notes for this book yet.")
            : AppText.localized("没有匹配的阅读笔记。", "No matching reading notes.")
    }

    /// Resolves a row back to its note.
    ///
    /// Rows carry only an id, so acting on one has to find the note again — and
    /// the note may be gone, since the list can be redrawn from a store that
    /// changed underneath it (a delete elsewhere, an export reload).
    package static func note(withID id: String, in notes: [ReadingNote]) -> ReadingNote? {
        notes.first { $0.id == id }
    }

    package static func row(for note: ReadingNote) -> ReadingNoteListRowViewModel {
        ReadingNoteListRowViewModel(
            id: note.id,
            locationText: locationText(for: note),
            titleText: ReadingNoteTextPolicy.compactInlineText(note.displayTitle, maxLength: 96),
            isFavorite: note.isFavorite
        )
    }

    private static func locationText(for note: ReadingNote) -> String {
        if let first = note.locator.pdfFragments?.first {
            return AppText.localized("第 \(first.pageIndex + 1) 页", "p. \(first.pageIndex + 1)")
        }
        return AppText.localized("网页位置", "Web location")
    }

    private static func searchableText(for note: ReadingNote) -> String {
        [
            note.displayTitle,
            locationText(for: note),
            note.quote,
            note.markdown,
            note.documentTitle
        ].joined(separator: "\n")
    }
}
