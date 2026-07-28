import Foundation
import LeafReaderCore

struct ReaderNotesState {
    var storedReadingNotes: [ReadingNote] = []
    var panelControllers: [String: ReadingNotePanelController] = [:]
}
