import Foundation

struct ReaderNotesState {
    var storedReadingNotes: [ReadingNote] = []
    var panelControllers: [String: ReadingNotePanelController] = [:]
}
