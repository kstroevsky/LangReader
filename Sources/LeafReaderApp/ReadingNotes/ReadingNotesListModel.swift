import Foundation
import Observation

/// State behind the Reading Notes list.
///
/// Everything the list shows is derived from two stored values — the notes and
/// the search query — so there is no cached row array to fall out of step with
/// them. `ReadingNoteListPresenter` still owns the rules (sorting, filtering,
/// the summary and empty-state wording); this type only holds the state those
/// rules run against and routes the row actions back to real notes.
@Observable
final class ReadingNotesListModel {
    /// Notes in display order. Sorting happens once here rather than on every
    /// row rebuild.
    private(set) var notes: [ReadingNote] = []
    var searchQuery: String = ""
    /// Drives the list's colours. Set by the panel when the reader theme
    /// changes, which is what makes SwiftUI re-render into the new palette.
    var theme: ReaderTheme = ReaderTheme.selected

    var onOpenNote: ((ReadingNote) -> Void)?
    var onDeleteNote: ((ReadingNote) -> Void)?
    var onToggleFavorite: ((ReadingNote) -> Void)?
    var onExport: (() -> Void)?
    var onClose: (() -> Void)?

    var rows: [ReadingNoteListRowViewModel] {
        ReadingNoteListPresenter.rows(for: notes, query: searchQuery)
    }

    var summaryText: String {
        ReadingNoteListPresenter.summaryText(
            matchCount: rows.count,
            totalCount: notes.count,
            query: searchQuery
        )
    }

    var emptyStateText: String {
        ReadingNoteListPresenter.emptyStateText(query: searchQuery)
    }

    func update(notes: [ReadingNote]) {
        self.notes = ReadingNoteListPresenter.sortedNotes(notes)
    }

    // MARK: Row actions

    /// Rows carry only an id, so an action has to resolve back to the note.
    /// A row whose note has since disappeared is ignored rather than
    /// force-unwrapped.
    func open(rowID: String) { perform(rowID, onOpenNote) }
    func toggleFavorite(rowID: String) { perform(rowID, onToggleFavorite) }
    func delete(rowID: String) { perform(rowID, onDeleteNote) }

    private func perform(_ rowID: String, _ handler: ((ReadingNote) -> Void)?) {
        guard let note = ReadingNoteListPresenter.note(withID: rowID, in: notes) else { return }
        handler?(note)
    }
}
